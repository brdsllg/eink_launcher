import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:eink_launcher/reader/services/doc_identity_service.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('doc_id_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'computes identical docId for identical contents at different paths',
    () async {
      final fileA = File('${tempDir.path}/book_a.pdf');
      final fileB = File('${tempDir.path}/renamed_book.pdf');

      final sampleContent = List.filled(1000, 65); // 1000 'A' characters
      await fileA.writeAsBytes(sampleContent);
      await fileB.writeAsBytes(sampleContent);

      final idA = await DocIdentityService.computeDocId(fileA.path);
      final idB = await DocIdentityService.computeDocId(fileB.path);

      expect(idA, equals(idB));
      expect(idA.isNotEmpty, isTrue);
    },
  );

  test('computes different docId when content or size changes', () async {
    final fileA = File('${tempDir.path}/book_a.pdf');
    final fileB = File('${tempDir.path}/book_b.pdf');

    await fileA.writeAsBytes(List.filled(1000, 65));
    await fileB.writeAsBytes(List.filled(1001, 65));

    final idA = await DocIdentityService.computeDocId(fileA.path);
    final idB = await DocIdentityService.computeDocId(fileB.path);

    expect(idA, isNot(equals(idB)));
  });
}
