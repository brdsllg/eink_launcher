import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/doc_ref.dart';

class DocIdentityService {
  static const int _sampleBytes = 64 * 1024; // 64 KB

  /// Generates a stable unique ID: sha1(first 64 KB + fileSize).
  static Future<String> computeDocId(String filePath) async {
    final file = File(filePath);
    final stat = await file.stat();
    final fileSize = stat.size;

    final stream = file.openRead(
      0,
      fileSize < _sampleBytes ? fileSize : _sampleBytes,
    );
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }

    // Append file size string to byte stream
    final sizeBytes = fileSize.toString().codeUnits;
    bytes.addAll(sizeBytes);

    return sha1.convert(bytes).toString();
  }

  /// Creates a [DocRef] from a given file path.
  static Future<DocRef> createDocRef(String filePath) async {
    final file = File(filePath);
    final stat = await file.stat();
    final id = await computeDocId(filePath);
    final fileName = filePath.split('/').last;
    final dotIndex = fileName.lastIndexOf('.');
    final ext = dotIndex != -1 ? fileName.substring(dotIndex) : '';
    final title = dotIndex != -1 ? fileName.substring(0, dotIndex) : fileName;

    return DocRef(
      id: id,
      path: filePath,
      format: DocFormat.fromExtension(ext),
      title: title,
      fileSize: stat.size,
    );
  }
}
