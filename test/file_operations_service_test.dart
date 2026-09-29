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

  group('recycle bin', () {
    late DateTime clock;
    late FileOperationsService bin;

    setUp(() {
      clock = DateTime(2026, 1, 1);
      bin = FileOperationsService(trashRoot: p2('.bin'), now: () => clock);
    });

    bool inBin(String name) =>
        FileSystemEntity.typeSync(
          '${bin.trashItemsDir}/$name',
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound;

    test('trashEntries moves items into the bin; restore puts them back', () async {
      Directory(p2('docs')).createSync();
      writeFile('docs/a.txt', 'A');
      final errors = await bin.trashEntries([p2('docs/a.txt')]);
      expect(errors, isEmpty);
      expect(exists('docs/a.txt'), isFalse);
      expect(inBin('a.txt'), isTrue);

      final restoreErrors = await bin.restoreEntries([
        '${bin.trashItemsDir}/a.txt',
      ]);
      expect(restoreErrors, isEmpty);
      expect(File(p2('docs/a.txt')).readAsStringSync(), 'A');
      expect(inBin('a.txt'), isFalse);
    });

    test('trashing a folder keeps its contents', () async {
      Directory(p2('proj/sub')).createSync(recursive: true);
      writeFile('proj/sub/n.txt', 'N');
      expect(await bin.trashEntries([p2('proj')]), isEmpty);
      expect(exists('proj'), isFalse);
      expect(inBin('proj/sub/n.txt'), isTrue);
    });

    test(
      'same-named items get unique bin names and restore to their own folders',
      () async {
        Directory(p2('one')).createSync();
        Directory(p2('two')).createSync();
        writeFile('one/a.txt', '1');
        writeFile('two/a.txt', '2');
        await bin.trashEntries([p2('one/a.txt'), p2('two/a.txt')]);
        expect(inBin('a.txt'), isTrue);
        expect(inBin('a (1).txt'), isTrue);

        final errors = await bin.restoreEntries([
          '${bin.trashItemsDir}/a.txt',
          '${bin.trashItemsDir}/a (1).txt',
        ]);
        expect(errors, isEmpty);
        expect(File(p2('one/a.txt')).readAsStringSync(), '1');
        expect(File(p2('two/a.txt')).readAsStringSync(), '2');
      },
    );

    test('restore recreates a missing parent folder', () async {
      Directory(p2('deep/nested')).createSync(recursive: true);
      writeFile('deep/nested/f.txt', 'F');
      await bin.trashEntries([p2('deep/nested/f.txt')]);
      await ops.deleteEntries([p2('deep')]);
      expect(exists('deep'), isFalse);

      final errors = await bin.restoreEntries(['${bin.trashItemsDir}/f.txt']);
      expect(errors, isEmpty);
      expect(File(p2('deep/nested/f.txt')).readAsStringSync(), 'F');
    });

    test('restore never overwrites something now at the original path', () async {
      writeFile('a.txt', 'old');
      await bin.trashEntries([p2('a.txt')]);
      writeFile('a.txt', 'new');

      final errors = await bin.restoreEntries(['${bin.trashItemsDir}/a.txt']);
      expect(errors, isEmpty);
      expect(File(p2('a.txt')).readAsStringSync(), 'new');
      expect(File(p2('a (1).txt')).readAsStringSync(), 'old');
    });

    test('trashEntries reports a missing item without aborting the rest', () async {
      writeFile('keep.txt');
      final errors = await bin.trashEntries([p2('missing'), p2('keep.txt')]);
      expect(errors, hasLength(1));
      expect(inBin('keep.txt'), isTrue);
    });

    test('purgeExpiredTrash removes only items older than 30 days', () async {
      writeFile('old.txt');
      await bin.trashEntries([p2('old.txt')]);
      clock = clock.add(const Duration(days: 20));
      writeFile('new.txt');
      await bin.trashEntries([p2('new.txt')]);

      // old.txt is now 31 days in the bin, new.txt only 11.
      clock = clock.add(const Duration(days: 11));
      expect(await bin.purgeExpiredTrash(), 1);
      expect(inBin('old.txt'), isFalse);
      expect(inBin('new.txt'), isTrue);

      // new.txt reaches 31 days.
      clock = clock.add(const Duration(days: 20));
      expect(await bin.purgeExpiredTrash(), 1);
      expect(inBin('new.txt'), isFalse);
    });

    test('an item exactly 30 days old is still kept', () async {
      writeFile('a.txt');
      await bin.trashEntries([p2('a.txt')]);
      clock = clock.add(const Duration(days: 30));
      expect(await bin.purgeExpiredTrash(), 0);
      expect(inBin('a.txt'), isTrue);
    });

    test('items with no record are adopted, not purged on sight', () async {
      Directory(bin.trashItemsDir).createSync(recursive: true);
      File('${bin.trashItemsDir}/stray.txt').writeAsStringSync('s');
      clock = clock.add(const Duration(days: 400));
      expect(await bin.purgeExpiredTrash(), 0);
      expect(inBin('stray.txt'), isTrue);

      clock = clock.add(const Duration(days: 31));
      expect(await bin.purgeExpiredTrash(), 1);
      expect(inBin('stray.txt'), isFalse);
    });

    test('purging an empty or missing bin is harmless', () async {
      expect(await bin.purgeExpiredTrash(), 0);
      bin.ensureTrashDir();
      expect(await bin.purgeExpiredTrash(), 0);
    });

    test('deleteFromTrash removes items for good and forgets them', () async {
      writeFile('a.txt');
      await bin.trashEntries([p2('a.txt')]);
      final errors = await bin.deleteFromTrash(['${bin.trashItemsDir}/a.txt']);
      expect(errors, isEmpty);
      expect(inBin('a.txt'), isFalse);

      // The name is free again, so no " (1)" suffix is needed.
      writeFile('a.txt');
      await bin.trashEntries([p2('a.txt')]);
      expect(inBin('a.txt'), isTrue);
      expect(inBin('a (1).txt'), isFalse);
    });

    test('trashDaysRemaining counts down from 30, rounding up', () async {
      writeFile('a.txt');
      await bin.trashEntries([p2('a.txt')]);
      expect(bin.trashDaysRemaining(), {'a.txt': 30});

      clock = clock.add(const Duration(days: 1, hours: 1));
      expect(bin.trashDaysRemaining()['a.txt'], 29);

      clock = clock.add(const Duration(days: 28));
      expect(bin.trashDaysRemaining()['a.txt'], 1); // 22 hours left

      clock = clock.add(const Duration(days: 2));
      expect(bin.trashDaysRemaining()['a.txt'], 0); // overdue, never negative
    });

    test('emptyTrash permanently removes everything in the bin', () async {
      Directory(p2('d')).createSync();
      writeFile('d/x.txt');
      writeFile('a.txt');
      await bin.trashEntries([p2('d'), p2('a.txt')]);

      expect(await bin.emptyTrash(), isEmpty);
      expect(inBin('d'), isFalse);
      expect(inBin('a.txt'), isFalse);
      expect(bin.trashDaysRemaining(), isEmpty);
    });

    test('emptyTrash on a bin that does not exist yet is harmless', () async {
      final fresh = FileOperationsService(trashRoot: p2('.never-used'));
      expect(await fresh.emptyTrash(), isEmpty);
    });

    test('isInTrash covers the bin folder and everything inside it', () {
      expect(bin.isInTrash(bin.trashItemsDir), isTrue);
      expect(bin.isInTrash('${bin.trashItemsDir}/x/y'), isTrue);
      expect(bin.isInTrash(p2('other')), isFalse);
      expect(bin.isInTrash('${bin.trashItemsDir}-not'), isFalse);
      expect(bin.isTrashRoot(bin.trashItemsDir), isTrue);
      expect(bin.isTrashRoot('${bin.trashItemsDir}/x'), isFalse);
    });
  });
}
