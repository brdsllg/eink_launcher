import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'reader/controllers/reader_session_registry.dart';
import 'screens/file_browser_screen.dart';
import 'services/launcher_error_service.dart';

void main() {
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
  runApp(const MyApp());
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
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Ink Launcher',
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
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black,
            side: const BorderSide(color: Colors.black, width: 1.5),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: Colors.black),
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
