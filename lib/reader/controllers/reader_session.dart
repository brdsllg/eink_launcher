import 'package:flutter/foundation.dart';

import '../models/doc_ref.dart';
import '../models/reader_settings.dart';
import '../models/reading_position.dart';
import '../models/toc_entry.dart';

/// Lifecycle and navigation contract shared by every reader session.
///
/// A session is long-lived and is not tied to a [Navigator] route: tab
/// support (READER_PLAN.md §1.A) requires state to survive being hidden.
/// [ReaderSessionRegistry] owns creation, suspension, and disposal; screens
/// are pure views over whatever session they are handed.
///
/// [PdfReaderSession] is the only implementation so far (Phase 1). A
/// `TextReaderSession` covering EPUB/TXT/MD arrives in Phase 2.
abstract class ReaderSession extends ChangeNotifier {
  DocRef get doc;

  /// True once [open] (or [resume]) has completed successfully and the
  /// session can navigate and render.
  bool get isReady;

  /// True after [suspend] and before [resume] completes.
  bool get isSuspended;

  /// Set when [open], [resume], or a navigation call fails. Cleared on the
  /// next successful operation.
  String? get error;

  /// Total page count. Survives [suspend] so the UI (page X of Y, TOC, jump
  /// dialogs) doesn't flicker while a session is hidden. May grow for
  /// formats with background pagination; listeners are notified when it does.
  int get pageCount;

  /// Current page, 0-based.
  int get currentPage;

  /// Fraction of the document read so far, in `[0.0, 1.0]`.
  double get percent;

  /// The current logical position. This — never a page number — is what
  /// [BookStoreService] persists (READER_PLAN.md §1.B), because page numbers
  /// shift under font size, margin, rotation, and crop changes.
  ReadingPosition get position;

  List<TocEntry> get toc;

  ReaderSettings get settings;

  /// Opens the underlying document and restores the last saved position.
  Future<void> open();

  Future<void> nextPage();
  Future<void> prevPage();
  Future<void> goToPage(int pageIndex);
  Future<void> goToToc(TocEntry entry);
  Future<void> goToPercent(double pct);
  Future<void> applySettings(ReaderSettings settings);

  /// Frees rendered bitmaps and closes native handles but keeps [position],
  /// [toc], and [pageCount] so the session can be shown again instantly.
  /// Safe to call when already suspended.
  void suspend();

  /// Reopens native handles at the position left by [suspend]. Safe to call
  /// when not suspended.
  Future<void> resume();
}
