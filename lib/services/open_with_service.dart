import 'package:flutter/services.dart';

import 'file_mime_type_service.dart';

/// Opens Android's app chooser for a file, even when a default app is set.
class OpenWithService {
  static const _channel = MethodChannel('eink_launcher/open_with');

  const OpenWithService._();

  static Future<void> open(String path) {
    return _channel.invokeMethod<void>('openWith', {
      'path': path,
      'mimeType': FileMimeTypeService.forPath(path),
    });
  }
}
