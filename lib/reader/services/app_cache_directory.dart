// Resolves the app cache directory, selecting the implementation by
// platform: the Flutter/path_provider version where dart:ui exists
// (device, flutter test), a pure-Dart fallback for `dart run` laptop
// tooling (tool/build_study_index.dart) which has no Flutter engine.
import 'app_cache_directory_stub.dart'
    if (dart.library.ui) 'app_cache_directory_flutter.dart'
    as impl;

import 'dart:io';

Future<Directory> getAppCacheDirectory() => impl.getAppCacheDirectory();
