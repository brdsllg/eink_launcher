// Prebuilds a ready-made per-book SQLite index for study EPUBs.
//
// Mirrors what TanachSqliteCacheService._writeDatabase produces on the device,
// so the reader can open the sidecar with zero import work. The pipeline runs
// this once per book on the laptop; you copy the .epub + .study.sqlite pair
// onto the device.
//
// Usage:
//   dart run tool/build_study_index.dart <book.epub> [--out <dir>]
//   dart run tool/build_study_index.dart <books-dir> [--out <dir>]
//
// Fingerprint rule: the reader accepts a cached database only when its stored
// `fingerprint` equals the SHA-256 of the EPUB file bytes
// (ParsedEpubCacheService._fingerprint). This tool hashes the same EPUB bytes,
// so the sidecar validates on first open.
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:eink_launcher/reader/services/epub_parser_service.dart';
import 'package:eink_launcher/reader/services/tanach_layout_service.dart';
import 'package:eink_launcher/reader/services/tanach_sqlite_cache_service.dart';

Future<void> main(List<String> args) async {
  final positional = <String>[];
  String? outDir;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--out' && i + 1 < args.length) {
      outDir = args[++i];
    } else if (args[i].startsWith('--out=')) {
      outDir = args[i].substring('--out='.length);
    } else if (!args[i].startsWith('-')) {
      positional.add(args[i]);
    } else {
      stderr.writeln('Unknown flag: ${args[i]}');
      exit(2);
    }
  }
  if (positional.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/build_study_index.dart <book.epub|books-dir> [--out <dir>]',
    );
    exit(2);
  }
  final input = File(positional.single).absolute;
  final inputDir = Directory(positional.single).absolute;
  final epubs = <File>[];
  if (await FileSystemEntity.isFile(input.path) &&
      input.path.toLowerCase().endsWith('.epub')) {
    epubs.add(input);
  } else if (await Directory(inputDir.path).exists()) {
    for (final entity in inputDir.listSync()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.epub')) {
        epubs.add(entity);
      }
    }
    epubs.sort((a, b) => a.path.compareTo(b.path));
  }
  if (epubs.isEmpty) {
    stderr.writeln('No .epub files found at ${positional.single}');
    exit(1);
  }
  final out = outDir == null ? null : Directory(outDir).absolute;
  if (out != null) await out.create(recursive: true);
  var failures = 0;
  for (final epub in epubs) {
    try {
      final target = await buildSidecar(epub, outDir: out);
      final size = await target.length();
      stdout.writeln(
        'wrote ${target.path} (${(size / 1048576).toStringAsFixed(1)} MB)',
      );
    } catch (error) {
      failures++;
      stderr.writeln('FAILED ${epub.path}: $error');
    }
  }
  if (failures > 0) exit(1);
}

/// Parses [epub], imports it into the device cache schema, and writes the
/// sidecar next to the book (or into [outDir]). Returns the sidecar file.
Future<File> buildSidecar(File epub, {Directory? outDir}) async {
  final bytes = await epub.readAsBytes();
  final epubBase = epub.uri.pathSegments.last.replaceAll(
    RegExp(r'\.epub$', caseSensitive: false),
    '',
  );
  final sidecar = File(
    outDir == null
        ? '${File(epub.path).parent.path}/$epubBase.study.sqlite'
        : '${outDir.path}/$epubBase.study.sqlite',
  );
  await sidecar.parent.create(recursive: true);
  final book = await const EpubParserService().parseBytes(
    Uint8List.fromList(bytes),
    honorPublisherCss: true,
    projectStudy: false,
  );
  if (book.studyDocuments.isEmpty) {
    throw StateError(
      '${epub.path} is not a recognized study book; no index written.',
    );
  }
  final laidOut = TanachLayoutService.layout(book, const _DefaultProjection());
  final fingerprint = _epubFingerprint(bytes);
  final temp = File(
    '${sidecar.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await TanachSqliteCacheService.writeDatabaseForExport(
      temp.path,
      laidOut,
      fingerprint,
    );
    if (await sidecar.exists()) await sidecar.delete();
    await temp.rename(sidecar.path);
  } finally {
    if (await temp.exists()) {
      try {
        await temp.delete();
      } catch (_) {}
    }
  }
  final index = await TanachSqliteCacheService.readSkeletonForExport(
    sidecar.path,
    fingerprint: fingerprint,
  );
  if (index == null) {
    throw StateError('Wrote ${sidecar.path} but it failed to validate.');
  }
  return sidecar;
}

/// Byte-identical to ParsedEpubCacheService._fingerprint (SHA-256 of the EPUB
/// file bytes): the device recomputes this from the EPUB file on disk, so the
/// sidecar's stored fingerprint must match byte-for-byte.
String _epubFingerprint(Uint8List bytes) => sha256.convert(bytes).toString();

/// Default projection, matching the reader's first-open import exactly: no
/// commentary selected, both languages, exported default translation, honor
/// publisher CSS, chapter table of contents.
class _DefaultProjection implements StudyProjectionSettings {
  const _DefaultProjection();
  @override
  List<String> get commentarySources => const [];
  @override
  String get commentaryLanguage => 'both';
  @override
  String get verseLanguage => 'both';
  @override
  String get studyTranslation => '';
  @override
  bool get honorPublisherCss => true;
  @override
  bool get showParshaAliyot => false;
  @override
  bool get hideVowelPoints => false;
  @override
  bool get studyContinuous => false;
}
