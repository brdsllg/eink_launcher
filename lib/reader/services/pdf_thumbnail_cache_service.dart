import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'pdf_crop_service.dart';

/// Bounded disk cache for coarse whole-page PDF previews.
///
/// The cache stores encoded PNGs, so retained disk entries do not consume the
/// session's decoded bitmap budget. Callers own images returned by [load].
/// [store] takes ownership of its image and always disposes it.
class PdfThumbnailCacheService {
  static PdfThumbnailCacheService? _instance;
  static PdfThumbnailCacheService get instance =>
      _instance ??= PdfThumbnailCacheService._();

  static const int cacheVersion = 1;
  static const int defaultMaxBytes = 64 * 1024 * 1024;

  final Directory? cacheDirectory;
  final int maxBytes;

  Directory? _resolvedDirectory;
  Future<void>? _initialization;
  Future<void> _writeTail = Future<void>.value();
  final Map<String, _ThumbnailDiskEntry> _entries = {};
  final Map<String, Future<void>> _pendingStores = {};

  PdfThumbnailCacheService._({
    this.cacheDirectory,
    this.maxBytes = defaultMaxBytes,
  });

  PdfThumbnailCacheService.forTesting({
    required Directory cacheDirectory,
    int maxBytes = defaultMaxBytes,
  }) : this._(cacheDirectory: cacheDirectory, maxBytes: maxBytes);

  String keyFor({
    required String docId,
    required int pageIndex,
    required int pixelWidth,
    required int pixelHeight,
    required PdfCropRect crop,
  }) {
    final source = jsonEncode({
      'version': cacheVersion,
      'docId': docId,
      'pageIndex': pageIndex,
      'pixelWidth': pixelWidth,
      'pixelHeight': pixelHeight,
      'crop': [
        crop.left.toStringAsFixed(6),
        crop.top.toStringAsFixed(6),
        crop.right.toStringAsFixed(6),
        crop.bottom.toStringAsFixed(6),
      ],
    });
    return sha256.convert(utf8.encode(source)).toString();
  }

  Future<bool> contains(String key) async {
    await _ensureInitialized();
    final pending = _pendingStores[key];
    if (pending != null) await pending;
    final entry = _entries[key];
    if (entry == null) return false;
    if (!await entry.file.exists()) {
      _entries.remove(key);
      return false;
    }
    entry.touched = DateTime.now();
    return true;
  }

  Future<ui.Image?> load(String key) async {
    await _ensureInitialized();
    final pending = _pendingStores[key];
    if (pending != null) await pending;
    final entry = _entries[key];
    if (entry == null) return null;
    try {
      final bytes = await entry.file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        entry.touched = DateTime.now();
        unawaited(entry.file.setLastModified(entry.touched).catchError((_) {}));
        return frame.image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      _entries.remove(key);
      try {
        if (await entry.file.exists()) await entry.file.delete();
      } catch (_) {}
      return null;
    }
  }

  /// Encodes and stores [image]. Ownership transfers to this service.
  Future<void> store(String key, ui.Image image) {
    final existing = _pendingStores[key];
    if (existing != null) {
      image.dispose();
      return existing;
    }
    final operation = _storeOwned(key, image);
    _pendingStores[key] = operation;
    operation.whenComplete(() {
      if (identical(_pendingStores[key], operation)) {
        _pendingStores.remove(key);
      }
    });
    return operation;
  }

  Future<void> _storeOwned(String key, ui.Image image) async {
    try {
      await _ensureInitialized();
      if (_entries.containsKey(key)) {
        _entries[key]!.touched = DateTime.now();
        return;
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await _enqueueWrite(key, Uint8List.fromList(bytes));
    } catch (_) {
      // A disk preview is optional; native rendering remains the fallback.
    } finally {
      image.dispose();
    }
  }

  Future<void> _enqueueWrite(String key, Uint8List bytes) {
    final operation = _writeTail.then((_) => _writeBytes(key, bytes));
    _writeTail = operation.catchError((_) {});
    return operation;
  }

  Future<void> _writeBytes(String key, Uint8List bytes) async {
    final directory = _resolvedDirectory!;
    final file = File('${directory.path}/$key.png');
    if (await file.exists()) {
      final stat = await file.stat();
      _entries[key] = _ThumbnailDiskEntry(file, stat.size, DateTime.now());
      return;
    }
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp',
    );
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
      _entries[key] = _ThumbnailDiskEntry(file, bytes.length, DateTime.now());
      await _evictToBudget();
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
    }
  }

  Future<void> _ensureInitialized() {
    final existing = _initialization;
    if (existing != null) return existing;
    final operation = _initialize();
    _initialization = operation;
    return operation;
  }

  Future<void> _initialize() async {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
    final directory =
        cacheDirectory ??
        Directory(
          '${(await getApplicationCacheDirectory()).path}/pdf_previews',
        );
    _resolvedDirectory = directory;
    await directory.create(recursive: true);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.tmp')) {
        try {
          await entity.delete();
        } catch (_) {}
        continue;
      }
      if (!entity.path.endsWith('.png')) continue;
      try {
        final stat = await entity.stat();
        final name = entity.uri.pathSegments.last;
        final key = name.substring(0, name.length - '.png'.length);
        _entries[key] = _ThumbnailDiskEntry(entity, stat.size, stat.modified);
      } catch (_) {}
    }
    await _evictToBudget();
  }

  Future<void> _evictToBudget() async {
    var total = _entries.values.fold<int>(0, (sum, entry) => sum + entry.bytes);
    if (total <= maxBytes) return;
    final oldestFirst = _entries.entries.toList()
      ..sort((a, b) => a.value.touched.compareTo(b.value.touched));
    for (final candidate in oldestFirst) {
      if (total <= maxBytes) break;
      _entries.remove(candidate.key);
      total -= candidate.value.bytes;
      try {
        if (await candidate.value.file.exists()) {
          await candidate.value.file.delete();
        }
      } catch (_) {}
    }
  }
}

class _ThumbnailDiskEntry {
  final File file;
  final int bytes;
  DateTime touched;

  _ThumbnailDiskEntry(this.file, this.bytes, this.touched);
}
