import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which part of the panel is usable, for a screen with damaged edges.
///
/// The two sizes are physical pixels measured with the tablet held upright in
/// its natural portrait position (1264 x 1680 on the Bigme B751C): how much of
/// the right edge and how much of the bottom edge cannot be read.
@immutable
class ScreenEdgeSettings {
  const ScreenEdgeSettings({
    required this.enabled,
    required this.rightPx,
    required this.bottomPx,
  });

  final bool enabled;
  final int rightPx;
  final int bottomPx;

  ScreenEdgeSettings copyWith({bool? enabled, int? rightPx, int? bottomPx}) {
    return ScreenEdgeSettings(
      enabled: enabled ?? this.enabled,
      rightPx: rightPx ?? this.rightPx,
      bottomPx: bottomPx ?? this.bottomPx,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ScreenEdgeSettings &&
      other.enabled == enabled &&
      other.rightPx == rightPx &&
      other.bottomPx == bottomPx;

  @override
  int get hashCode => Object.hash(enabled, rightPx, bottomPx);
}

/// Keeps the app's content inside the readable part of a cracked panel.
///
/// Measured on the owner's Bigme B751C (see docs/DEVICE_TESTING.md): upright,
/// the right edge is lost from x = 1017 px and the bottom from y = 1340 px.
/// Held sideways the same damage reads 1353 px / 253 px. The larger loss on
/// each edge is used: 253 px on the right and 340 px at the bottom.
class ScreenInsetsService {
  ScreenInsetsService._();

  static final ScreenInsetsService instance = ScreenInsetsService._();

  static const int defaultRightPx = 253;
  static const int defaultBottomPx = 340;

  static const _channel = MethodChannel('eink_launcher/display');
  static const _enabledKey = 'screen_edges_enabled';
  static const _rightKey = 'screen_edges_right_px';
  static const _bottomKey = 'screen_edges_bottom_px';

  final ValueNotifier<ScreenEdgeSettings> settings = ValueNotifier(
    const ScreenEdgeSettings(
      enabled: true,
      rightPx: defaultRightPx,
      bottomPx: defaultBottomPx,
    ),
  );

  /// Reads saved settings. Never throws: on any problem the defaults stay.
  Future<void> load() async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      settings.value = ScreenEdgeSettings(
        enabled: prefs.getBool(_enabledKey) ?? true,
        rightPx: prefs.getInt(_rightKey) ?? defaultRightPx,
        bottomPx: prefs.getInt(_bottomKey) ?? defaultBottomPx,
      );
    } catch (error) {
      debugPrint('Screen edge settings could not be read: $error');
    }
  }

  Future<void> save(ScreenEdgeSettings value) async {
    settings.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value.enabled);
      await prefs.setInt(_rightKey, value.rightPx);
      await prefs.setInt(_bottomKey, value.bottomPx);
    } catch (error) {
      debugPrint('Screen edge settings could not be saved: $error');
    }
  }

  Future<void> reset() => save(
    const ScreenEdgeSettings(
      enabled: true,
      rightPx: defaultRightPx,
      bottomPx: defaultBottomPx,
    ),
  );

  /// Android's display rotation: 0 upright, 1 turned 90 degrees
  /// counter-clockwise (the browser's Landscape), 2 upside down, 3 turned
  /// 90 degrees clockwise. Returns 0 if it cannot be read.
  Future<int> rotation() async {
    if (!Platform.isAndroid) return 0;
    try {
      final value = await _channel.invokeMethod<int>('getRotation');
      if (value == null || value < 0 || value > 3) return 0;
      return value;
    } catch (_) {
      return 0;
    }
  }

  /// The blocked strip on each edge, in logical pixels, for the given display
  /// rotation. The damage is fixed to the panel, so as the tablet turns the
  /// right and bottom strips move to other edges:
  ///
  /// - 0 upright:                 right and bottom
  /// - 1 turned counter-clockwise: top and right
  /// - 2 upside down:             left and top
  /// - 3 turned clockwise:        bottom and left
  static EdgeInsets insetsFor(
    ScreenEdgeSettings settings,
    int rotation,
    double devicePixelRatio,
  ) {
    if (!settings.enabled || devicePixelRatio <= 0) return EdgeInsets.zero;
    final right = settings.rightPx / devicePixelRatio;
    final bottom = settings.bottomPx / devicePixelRatio;
    switch (rotation) {
      case 1:
        return EdgeInsets.fromLTRB(0, right, bottom, 0);
      case 2:
        return EdgeInsets.fromLTRB(right, bottom, 0, 0);
      case 3:
        return EdgeInsets.fromLTRB(bottom, 0, 0, right);
      default:
        return EdgeInsets.fromLTRB(0, 0, right, bottom);
    }
  }
}
