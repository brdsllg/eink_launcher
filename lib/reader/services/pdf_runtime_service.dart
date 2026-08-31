import 'package:pdfrx/pdfrx.dart';

/// Initializes PDFium only when the default document opener first needs it.
abstract final class PdfRuntimeService {
  static Future<void>? _initialization;

  /// All PDF opens and resumes share one future, including concurrent callers.
  /// Failures propagate to the reader's error boundary and remain memoized:
  /// restarting the app is required to retry a failed native initialization.
  static Future<void> ensureInitialized() {
    return _initialization ??= pdfrxFlutterInitialize();
  }
}
