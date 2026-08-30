import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:eink_launcher/services/file_operations_service.dart';

void main() {
  late Directory temp;
  late FileOperationsService ops;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('eink_ops_test_');
    ops = FileOperationsService();
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  String p2(String rel) => '${temp.path}/$rel';

  void writeFile(String rel, [String content = 'hello']) {
    File(p2(rel)).writeAsStringSync(content);
  }

  bool exists(String rel) =>
      FileSystemEntity.typeSync(p2(rel), followLinks: false) !=
      FileSystemEntityType.notFound;

  test('createFolder makes an empty directory', () async {
    await ops.createFolder(temp.path, 'NewDir');
    expect(Directory(p2('NewDir')).existsSync(), isTrue);
  });

  test('renameEntry renames a file and a folder', () async {
    writeFile('a.txt');
    Directory(p2('folder')).createSync();
    await ops.renameEntry(p2('a.txt'), 'b.txt');
    await ops.renameEntry(p2('folder'), 'renamed');
    expect(exists('a.txt'), isFalse);
    expect(exists('b.txt'), isTrue);
    expect(exists('renamed'), isTrue);
  });

  test('deleteEntries removes folders recursively and files', () async {
    Directory(p2('deep/nested')).createSync(recursive: true);
    writeFile('deep/nested/x.txt');
    writeFile('f.txt');
    final errors = await ops.deleteEntries([p2('deep'), p2('f.txt')]);
    expect(errors, isEmpty);
    expect(exists('deep'), isFalse);
    expect(exists('f.txt'), isFalse);
  });

  test(
    'deleteEntries reports per-item errors without aborting the rest',
    () async {
      writeFile('keep.txt');
      final errors = await ops.deleteEntries([p2('missing'), p2('keep.txt')]);
      expect(errors, hasLength(1));
      expect(exists('keep.txt'), isFalse);
    },
  );

  test(
    'copy + paste duplicates, keeps originals, then clears the clipboard',
    () async {
      writeFile('a.txt', 'content');
      ops.copy([p2('a.txt')]);
      final errors = await ops.paste(temp.path);
      expect(errors, isEmpty);
      expect(exists('a.txt'), isTrue);
      expect(File(p2('a.txt')).readAsStringSync(), 'content');
      // Auto-renamed copy is " (1)" before the extension.
      expect(File(p2('a (1).txt')).readAsStringSync(), 'content');
      // Single-use clipboard: cleared after a successful paste, so a second
      // paste pastes nothing.
      expect(ops.hasClipboard, isFalse);
      await ops.paste(temp.path);
      expect(exists('a (2).txt'), isFalse);
    },
  );

  test('cut + paste moves, removes originals, clears the clipboard', () async {
    // Source lives in a subfolder so the move is a true relocation.
    Directory(p2('src')).createSync();
    writeFile('src/m.txt');
    ops.cut([p2('src/m.txt')]);
    final errors = await ops.paste(temp.path);
    expect(errors, isEmpty);
    expect(exists('src/m.txt'), isFalse); // original moved
    expect(exists('m.txt'), isTrue); // now in the destination
    expect(File(p2('m.txt')).readAsStringSync(), 'hello');
    expect(ops.hasClipboard, isFalse); // cut+paste clears the clipboard
  });

  test('copy pastes a folder recursively', () async {
    Directory(p2('src/sub')).createSync(recursive: true);
    writeFile('src/a.txt');
    writeFile('src/sub/b.txt');
    ops.copy([p2('src')]);
    final errors = await ops.paste(temp.path);
    expect(errors, isEmpty);
    expect(File(p2('src (1)/a.txt')).readAsStringSync(), 'hello');
    expect(File(p2('src (1)/sub/b.txt')).readAsStringSync(), 'hello');
    expect(exists('src'), isTrue); // original untouched by copy
  });

  test(
    'pasting a folder into itself is refused, not recursed forever',
    () async {
      Directory(p2('folder')).createSync();
      writeFile('folder/f.txt');
      ops.copy([p2('folder')]);
      // Paste into the folder's own path (a descendant of itself guard).
      final errors = await ops.paste(p2('folder'));
      expect(errors, isNotEmpty);
      expect(exists('folder/f.txt'), isTrue);
    },
  );

  test(
    'conflicting paste auto-renames before the extension for files',
    () async {
      writeFile('report.txt');
      Directory(p2('copy')).createSync();
      writeFile('copy/report.txt');
      ops.copy([p2('copy/report.txt')]);
      final errors = await ops.paste(temp.path);
      expect(errors, isEmpty);
      expect(File(p2('report.txt')).readAsStringSync(), 'hello');
      expect(File(p2('report (1).txt')).readAsStringSync(), 'hello');
    },
  );

  test('conflicting paste auto-renames folders after the name', () async {
    Directory(p2('photos')).createSync();
    Directory(p2('extras/photos')).createSync(recursive: true);
    writeFile('extras/photos/pic.jpg');
    ops.copy([p2('extras/photos')]);
    final errors = await ops.paste(temp.path);
    expect(errors, isEmpty);
    expect(exists('photos (1)'), isTrue);
    expect(exists('photos (1)/pic.jpg'), isTrue);
  });
}
