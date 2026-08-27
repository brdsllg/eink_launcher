// Mode for a paste operation: copy keeps the originals, cut moves them.
enum ClipboardMode { copy, cut }

// Immutable snapshot of what's on the file-management clipboard. Both the
// action (copy/cut) and the selected absolute paths are stored together so
// "Paste" knows what to do and where the sources live.
//
// This is intentionally a simple value object held in memory by the screen's
// FileOperationsService — it is NOT written to disk, so it does not survive an
// app restart (per spec "no need to survive an app restart").
class ClipboardState {
  final List<String> paths;
  final ClipboardMode mode;

  const ClipboardState({required this.paths, required this.mode});
}
