// Device implementation: delegates to path_provider exactly as before.
import 'dart:io';

import 'package:path_provider/path_provider.dart' as provider;

Future<Directory> getAppCacheDirectory() =>
    provider.getApplicationCacheDirectory();
