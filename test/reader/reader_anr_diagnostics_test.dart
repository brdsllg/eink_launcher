import 'package:eink_launcher/reader/models/annotation.dart';
import 'package:eink_launcher/reader/models/content_block.dart';
import 'package:eink_launcher/reader/models/reader_settings.dart';
import 'package:eink_launcher/reader/services/epub_paginator_service.dart';
import 'package:eink_launcher/reader/services/reader_diagnostics.dart';
import 'package:eink_launcher/reader/widgets/block_slice_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ReaderDiagnostics.instance
      ..enabled = false
      ..reset();
  });

  test('diagnostics are off by default and stay bounded when enabled', () {
    final diagnostics = ReaderDiagnostics.instance;
    expect(diagnostics.enabled, isFalse);
    diagnostics.record('probe', const Duration(microseconds: 5));
    expect(diagnostics.summary(), isEmpty);
    expect(diagnostics.recent(), isEmpty);
    // Safe to call when disabled: prints nothing and throws nothing.
    diagnostics.dumpToLog();

    diagnostics.enabled = true;
    for (var i = 0; i < ReaderDiagnostics.maxEvents + 20; i++) {
      diagnostics.record('probe', Duration(microseconds: i + 1));
    }
    expect(diagnostics.recent().length, ReaderDiagnostics.maxEvents);
    final summary = diagnostics.summary();
    expect(summary['probe']!.count, lessThanOrEqualTo(256));
    expect(summary['probe']!.maxMicros, ReaderDiagnostics.maxEvents + 20);
    expect(
      summary['probe']!.p50Micros,
      lessThanOrEqualTo(summary['probe']!.p95Micros),
    );
    expect(
      summary['probe']!.p95Micros,
      lessThanOrEqualTo(summary['probe']!.maxMicros),
    );
    // Dumping with samples prints bounded lines and throws nothing.
    diagnostics.dumpToLog();
  });

  test(
    'cancelled responsive run publishes nothing and returns empty',
    () async {
      const paginator = EpubPaginatorService();
      final blocks = List.generate(
        64,
        (i) => ContentBlock(
          type: BlockType.paragraph,
          runs: [
            InlineRun(text: 'Block $i with enough words to measure. ' * 4),
          ],
        ),
      );
      var updates = 0;
      final result = await paginator.paginateSpineResponsive(
        spineIndex: 0,
        blocks: blocks,
        contentSize: const Size(260, 350),
        settings: const ReaderSettings(),
        isCancelled: () => true,
        onProgress: (_) => updates++,
      );
      expect(result, isEmpty);
      expect(updates, 0);
    },
  );

  test('responsive progress only reports growing page sets and matches sync geometry', () async {
    const paginator = EpubPaginatorService();
    // Tiny blocks on a tall page: mandatory batch yields see no completed
    // pages until the final snapshot, so unchanged sets must be skipped.
    final blocks = List.generate(
      48,
      (i) => const ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: 'Short line.')],
      ),
    );
    const size = Size(400, 2000);
    const settings = ReaderSettings();
    final expected = paginator.paginateSpine(
      spineIndex: 0,
      blocks: blocks,
      contentSize: size,
      settings: settings,
    );
    final lengths = <int>[];
    final actual = await paginator.paginateSpineResponsive(
      spineIndex: 0,
      blocks: blocks,
      contentSize: size,
      settings: settings,
      isCancelled: () => false,
      onProgress: (pages) => lengths.add(pages.length),
    );
    for (var i = 1; i < lengths.length; i++) {
      expect(lengths[i], greaterThan(lengths[i - 1]));
    }
    expect(actual.length, expected.length);
    for (var i = 0; i < actual.length; i++) {
      expect(actual[i].start, expected[i].start);
      expect(actual[i].end, expected[i].end);
    }
  });

  test('diagnostics do not change responsive pagination geometry', () async {
    const paginator = EpubPaginatorService();
    final blocks = List.generate(
      40,
      (i) => ContentBlock(
        type: BlockType.paragraph,
        runs: [InlineRun(text: 'Measured block $i with several words. ' * 5)],
      ),
    );
    const size = Size(260, 350);
    const settings = ReaderSettings();
    final expected = paginator.paginateSpine(
      spineIndex: 0,
      blocks: blocks,
      contentSize: size,
      settings: settings,
    );
    ReaderDiagnostics.instance.enabled = true;
    final actual = await paginator.paginateSpineResponsive(
      spineIndex: 0,
      blocks: blocks,
      contentSize: size,
      settings: settings,
      isCancelled: () => false,
      onProgress: (_) {},
    );
    expect(actual.length, expected.length);
    expect(
      ReaderDiagnostics.instance.summary().containsKey('paginator.measure'),
      isTrue,
    );
  });

  test('heartbeat stays stopped unless diagnostics are enabled', () {
    final heartbeat = ReaderHeartbeat();
    heartbeat.start();
    heartbeat.dispose();
    expect(ReaderDiagnostics.instance.heartbeatGapCount, 0);

    ReaderDiagnostics.instance.enabled = true;
    final active = ReaderHeartbeat(
      reportAbove: const Duration(hours: 1),
      interval: const Duration(milliseconds: 1),
    );
    active.start();
    active.dispose();
    expect(ReaderDiagnostics.instance.heartbeatGapCount, 0);
  });

  Annotation note(String id, int start, int end) => Annotation(
    id: id,
    docId: 'doc',
    createdAt: DateTime.utc(2026, 10, 16),
    spineIndex: 0,
    blockIndex: 2,
    startOffset: start,
    endOffset: end,
    text: 'sample',
  );

  test('annotation value comparison ignores fresh filtered lists', () {
    final first = [note('a', 0, 5), note('b', 6, 9)];
    final rebuilt = [note('a', 0, 5), note('b', 6, 9)];
    expect(identical(first, rebuilt), isFalse);
    expect(sameVisibleAnnotations(first, rebuilt), isTrue);
    expect(sameVisibleAnnotations(first, [note('a', 0, 5)]), isFalse);
    expect(
      sameVisibleAnnotations(first, [note('a', 0, 6), note('b', 6, 9)]),
      isFalse,
    );
    expect(
      sameVisibleAnnotations(first, [note('b', 6, 9), note('a', 0, 5)]),
      isFalse,
    );
    expect(sameVisibleAnnotations(const [], const []), isTrue);
  });
}
