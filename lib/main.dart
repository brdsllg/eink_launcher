import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';
import 'reader/controllers/reader_session_registry.dart';
import 'reader/screens/reader_screen.dart';
import 'reader/services/book_store_service.dart';
import 'reader/services/doc_identity_service.dart';
import 'reader/widgets/reading_state_warning.dart';
import 'screens/file_browser_screen.dart';
import 'services/file_intent_service.dart';
import 'services/launcher_error_service.dart';

Color? _buttonForeground(Set<WidgetState> states) {
  if (states.contains(WidgetState.disabled)) return Colors.grey;
  return states.contains(WidgetState.pressed) ? Colors.white : Colors.black;
}

Color? _buttonBackground(Set<WidgetState> states) =>
    states.contains(WidgetState.pressed) ? Colors.black : Colors.transparent;

final _pressedForeground = WidgetStateProperty.resolveWith<Color?>(
  _buttonForeground,
);
final _pressedBackground = WidgetStateProperty.resolveWith<Color?>(
  _buttonBackground,
);
const _squareButtonShape = WidgetStatePropertyAll<OutlinedBorder>(
  RoundedRectangleBorder(borderRadius: BorderRadius.zero),
);

void main() async {
  // Required before any SystemChrome/plugin calls in main().
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) LauncherErrorService.install();
  // Reader sessions can stay alive (with native PDF handles / parsed books)
  // in ReaderSessionRegistry even while the file browser, not the reader, is
  // on screen, so this is registered once for the whole app lifetime rather
  // than from ReaderScreen's own State: a State only exists while its screen
  // is mounted, but memory pressure can hit at any time.
  WidgetsBinding.instance.addObserver(ReaderMemoryPressureObserver());
  // Default the app to fullscreen at runtime (e-ink: hide status + nav bars).
  // The LaunchTheme/NormalTheme in styles.xml hide them from the moment the
  // process starts, and this keeps them hidden once Flutter takes over.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  
  // Start listening right away so no file-open is missed, but don't fetch
  // the launch file yet — MyApp sets its callback first, then initialize()
  // delivers it (or holds it until the callback exists).
  final fileIntentService = FileIntentService();
  fileIntentService.startListening();

  runApp(MyApp(fileIntentService: fileIntentService));
}

/// Forwards Android's `onTrimMemory`/`onLowMemory` signal (surfaced by
/// Flutter as [WidgetsBindingObserver.didHaveMemoryPressure]) to every open
/// reader session, wherever they are in the app's navigation stack.
///
/// [ReaderSessionRegistry] is a singleton, so this reaches sessions left
/// open from a previous visit to the reader even if the file browser is the
/// screen currently on top. Each session decides what "release memory" means
/// for its own format — see `ReaderSession.handleMemoryPressure`.
class ReaderMemoryPressureObserver with WidgetsBindingObserver {
  ReaderMemoryPressureObserver({ReaderSessionRegistry? registry})
    : _registry = registry ?? ReaderSessionRegistry.instance;

  final ReaderSessionRegistry _registry;

  @override
  void didHaveMemoryPressure() => _registry.handleMemoryPressure();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _registry.suspendAll();
      unawaited(BookStoreService.instance.flush());
    }
  }
}

class MyApp extends StatefulWidget {
  final FileIntentService fileIntentService;

  MyApp({FileIntentService? fileIntentService, super.key})
    : fileIntentService = fileIntentService ?? FileIntentService();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Set up callback for when files are opened with the app.
    widget.fileIntentService.onFileOpened = _handleFileIntent;
    unawaited(widget.fileIntentService.initialize());
  }

  @override
  void dispose() {
    widget.fileIntentService.dispose();
    super.dispose();
  }

  /// Handles a file path delivered from Android (open-with VIEW or share
  /// SEND). UI access goes through [_scaffoldMessengerKey]/[_navigatorKey]:
  /// this State's own context sits above MaterialApp, so ScaffoldMessenger
  /// and Navigator lookups on it throw.
  Future<void> _handleFileIntent(String filePath) async {
    if (!mounted) return;

    final trimmedPath = filePath.trim();
    debugPrint('File intent received: $trimmedPath');
    if (trimmedPath.isEmpty) return;

    void showMessage(String message) {
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message)),
      );
    }

    final file = File(trimmedPath);
    if (!file.existsSync()) {
      if (mounted) {
        showMessage('File no longer exists: $trimmedPath');
      }
      return;
    }

    // Shared files (share sheet / open-with) may arrive as application/octet-stream
    // or text/* with an unfamiliar extension. Fail fast with a clear message
    // instead of the raw "Unsupported format" ArgumentError.
    final fileName = trimmedPath.split('/').last.toLowerCase();
    final dotIndex = fileName.lastIndexOf('.');
    final extension = dotIndex > 0 ? fileName.substring(dotIndex) : '';
    if (!kReadableExtensions.contains(extension)) {
      if (mounted) {
        final shown = extension.isEmpty ? 'no file extension' : '$extension files';
        showMessage(
          'This app reads PDF, EPUB, TXT, and Markdown. '
          'Could not open $shown.',
        );
      }
      return;
    }

    try {
      final doc = await DocIdentityService.createDocRef(trimmedPath);
      if (!mounted) return;

      final navigator = _navigatorKey.currentState;
      if (navigator == null) {
        debugPrint('File intent dropped: navigator not ready for $trimmedPath');
        return;
      }
      await navigator.push(
        noTransitionRoute(
          ReaderScreen(doc: doc, registry: ReaderSessionRegistry.instance),
        ),
      );
    } catch (error, stack) {
      if (mounted) {
        debugPrint('File intent open failed: $error\n$stack');
        showMessage('Could not open file: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Ink Launcher',
      scaffoldMessengerKey: _scaffoldMessengerKey,
      navigatorKey: _navigatorKey,
      builder: (context, child) => ReadingStateWarning(
        store: BookStoreService.instance,
        child: child ?? const SizedBox.shrink(),
      ),
      // No "DEBUG" banner in the corner when running debug builds.
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Colors.black,
          onSecondary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
          error: Colors.black,
          onError: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        dividerColor: Colors.black,
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            iconSize: const WidgetStatePropertyAll(kReaderChromeIconSize),
            foregroundColor: _pressedForeground,
            backgroundColor: _pressedBackground,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: _squareButtonShape,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            foregroundColor: _pressedForeground,
            backgroundColor: _pressedBackground,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            side: const WidgetStatePropertyAll(
              BorderSide(color: Colors.black, width: 1.5),
            ),
            shape: _squareButtonShape,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: ButtonStyle(
            foregroundColor: _pressedForeground,
            backgroundColor: _pressedBackground,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: _squareButtonShape,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.zero),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Colors.black, width: 2),
          ),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.black, width: 1.5),
            borderRadius: BorderRadius.zero,
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Colors.black,
          linearTrackColor: Colors.white,
        ),
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      home: const FileBrowserScreen(),
    );
  }
}
