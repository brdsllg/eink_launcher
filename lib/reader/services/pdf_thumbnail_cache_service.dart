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
/// [loadOpeningPreview] resolves the cached first page without PDF geometry or
/// opening a document. Its small disk index refers to the same PNG files.
/// [store] takes ownership of its image and always disposes it.
class PdfThumbnailCacheService {
  static PdfThumbnailCacheService? _instance;
  static PdfThumbnailCacheService get instance =>
      _instance ??= PdfThumbnailCacheService._();

  static const int cacheVersion = 2;
  static const int defaultMaxBytes = 64 * 1024 * 1024;
  static const int maxOpeningPreviews = 1024;
  static const String _openingIndexName = 'opening-previews.json';

  final Directory? cacheDirectory;
  final int maxBytes;

  Directory? _resolvedDirectory;
  Future<void>? _initialization;
  Future<void> _writeTail = Future<void>.value();
  final Map<String, _ThumbnailDiskEntry> _entries = {};
  final Map<String, Future<void>> _pendingStores = {};
  final Map<String, String> _openingPreviewKeys = {};
  bool _openingIndexDirty = false;
  int _openingIndexRevision = 0;

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
    String renderProfile = 'gray-false',
  }) {
    final source = jsonEncode({
      'version': cacheVersion,
      'docId': docId,
      'renderProfile': renderProfile,
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

  Future<bool> contains(String key, {String? docId, int? pageIndex}) async {
    await _ensureInitialized();
    final pending = _pendingStores[key];
    if (pending != null) await pending;
    final entry = _entries[key];
    if (entry == null) return false;
    if (!await entry.file.exists()) {
      _removeEntry(key);
      await _enqueueWrite(_persistOpeningIndex);
      return false;
    }
    entry.touched = DateTime.now();
    await _recordOpeningPreview(key, docId: docId, pageIndex: pageIndex);
    return true;
  }

  /// Loads only an already-cached first page. A miss never renders a PDF page.
  /// The caller owns the returned image and must dispose it.
  Future<ui.Image?> loadOpeningPreview(String docId) async {
    try {
      await _ensureInitialized();
      final key = _openingPreviewKeys[docId];
      return key == null ? null : await load(key);
    } catch (_) {
      // Loading placeholders must remain usable if the cache is unavailable.
      return null;
    }
  }

  Future<ui.Image?> load(String key, {String? docId, int? pageIndex}) async {
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
        await _recordOpeningPreview(key, docId: docId, pageIndex: pageIndex);
        return frame.image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      _removeEntry(key);
      try {
        if (await entry.file.exists()) await entry.file.delete();
      } catch (_) {}
      await _enqueueWrite(_persistOpeningIndex);
      return null;
    }
  }

  /// Encodes and stores [image]. Ownership transfers to this service.
  Future<void> store(
    String key,
    ui.Image image, {
    String? docId,
    int? pageIndex,
  }) {
    final existing = _pendingStores[key];
    if (existing != null) {
      image.dispose();
      return existing.then(
        (_) => _recordOpeningPreview(key, docId: docId, pageIndex: pageIndex),
      );
    }
    final operation = _storeOwned(
      key,
      image,
      docId: docId,
      pageIndex: pageIndex,
    );
    _pendingStores[key] = operation;
    operation.whenComplete(() {
      if (identical(_pendingStores[key], operation)) {
        _pendingStores.remove(key);
      }
    });
    return operation;
  }

  Future<void> _storeOwned(
    String key,
    ui.Image image, {
    String? docId,
    int? pageIndex,
  }) async {
    try {
      await _ensureInitialized();
      if (_entries.containsKey(key)) {
        _entries[key]!.touched = DateTime.now();
        await _recordOpeningPreview(key, docId: docId, pageIndex: pageIndex);
        return;
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final encoded = Uint8List.fromList(bytes);
      await _enqueueWrite(() => _writeBytes(key, encoded));
      await _recordOpeningPreview(key, docId: docId, pageIndex: pageIndex);
    } catch (_) {
      // A disk preview is optional; native rendering remains the fallback.
    } finally {
      image.dispose();
    }
  }

  Future<void> _enqueueWrite(Future<void> Function() write) {
    final operation = _writeTail.then((_) => write());
    _writeTail = operation.catchError((_) {});
    return operation;
  }

  Future<void> _recordOpeningPreview(
    String key, {
    required String? docId,
    required int? pageIndex,
  }) async {
    if (docId == null || pageIndex != 0) return;
    // Store metadata only after the existing PNG is available. In particular,
    // oversized entries evicted immediately must not leave an opening alias.
    try {
      await _enqueueWrite(() async {
        if (!_entries.containsKey(key)) return;
        if (_openingPreviewKeys[docId] == key) {
          await _persistOpeningIndex();
          return;
        }
        _openingPreviewKeys.remove(docId);
        _openingPreviewKeys[docId] = key;
        while (_openingPreviewKeys.length > maxOpeningPreviews) {
          _openingPreviewKeys.remove(_openingPreviewKeys.keys.first);
        }
        _openingIndexDirty = true;
        _openingIndexRevision++;
        await _persistOpeningIndex();
      });
    } catch (_) {
      // An optional index write must not invalidate an otherwise usable image.
    }
  }

  void _removeEntry(String key) {
    _entries.remove(key);
    final count = _openingPreviewKeys.length;
    _openingPreviewKeys.removeWhere((_, value) => value == key);
    if (count != _openingPreviewKeys.length) {
      _openingIndexDirty = true;
      _openingIndexRevision++;
    }
  }

  Future<void> _persistOpeningIndex() async {
    if (!_openingIndexDirty) return;
    final file = File('${_resolvedDirectory!.path}/$_openingIndexName');
    final revision = _openingIndexRevision;
    final temporary = File('${file.path}.$pid.tmp');
    try {
      if (_openingPreviewKeys.isEmpty) {
        if (await file.exists()) await file.delete();
      } else {
        await temporary.writeAsString(
          jsonEncode({
            'version': cacheVersion,
            'firstPages': _openingPreviewKeys,
          }),
          flush: true,
        );
        await temporary.rename(file.path);
      }
      if (revision == _openingIndexRevision) _openingIndexDirty = false;
    } catch (_) {
      // Keep the in-memory index usable and retry persistence on a later hit.
    } finally {
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (_) {}
    }
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
    final operation = _initialize().catchError((
      Object error,
      StackTrace stack,
    ) {
      _initialization = null;
      Error.throwWithStackTrace(error, stack);
    });
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
    final index = File('${directory.path}/$_openingIndexName');
    if (await index.exists()) {
      try {
        final json = jsonDecode(await index.readAsString());
        if (json is Map && json['version'] == cacheVersion) {
          final firstPages = json['firstPages'];
          if (firstPages is Map) {
            for (final entry in firstPages.entries) {
              if (entry.key is String &&
                  entry.value is String &&
                  _entries.containsKey(entry.value)) {
                _openingPreviewKeys[entry.key as String] =
                    entry.value as String;
                if (_openingPreviewKeys.length > maxOpeningPreviews) {
                  _openingPreviewKeys.remove(_openingPreviewKeys.keys.first);
                }
              }
            }
          }
        }
      } catch (_) {
        // An incomplete or obsolete index is only a cache miss.
      }
      _openingIndexDirty = true;
      _openingIndexRevision++;
    }
    await _evictToBudget();
    await _persistOpeningIndex();
  }

  Future<void> _evictToBudget() async {
    var total = _entries.values.fold<int>(0, (sum, entry) => sum + entry.bytes);
    if (total <= maxBytes) return;
    final oldestFirst = _entries.entries.toList()
      ..sort((a, b) => a.value.touched.compareTo(b.value.touched));
    for (final candidate in oldestFirst) {
      if (total <= maxBytes) break;
      _removeEntry(candidate.key);
      total -= candidate.value.bytes;
      try {
        if (await candidate.value.file.exists()) {
          await candidate.value.file.delete();
        }
      } catch (_) {}
    }
    await _persistOpeningIndex();
  }
}

class _ThumbnailDiskEntry {
  final File file;
  final int bytes;
  DateTime touched;

  _ThumbnailDiskEntry(this.file, this.bytes, this.touched);
}
