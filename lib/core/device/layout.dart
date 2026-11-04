import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Kind of screen the app is laid out for.
enum FormFactor {
  /// < 600 dp: bottom tab bar.
  phone,

  /// 600–1199 dp (tablet, Chromebook): side rail, phone-sized content.
  tablet,

  /// ≥ 1200 dp or an Android TV: side rail, big type, remote-friendly focus.
  large,
}

/// Device facts read once at startup.
class DeviceInfo {
  DeviceInfo._();

  static const _channel = MethodChannel('app.vixeo/device');

  /// True on Android TV / Google TV (leanback). Set by [init].
  static bool isTv = false;

  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      isTv = await _channel.invokeMethod<bool>('isTv') ?? false;
    } on PlatformException {
      isTv = false;
    } on MissingPluginException {
      isTv = false;
    }
  }

  /// Label sent as `device_name` when logging in (shown in the account's sessions).
  static String get deviceName {
    if (kIsWeb) return 'Vixeo Web';
    if (isTv) return 'Vixeo TV';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Vixeo Android',
      TargetPlatform.iOS => 'Vixeo iPhone / iPad',
      TargetPlatform.macOS => 'Vixeo Mac',
      TargetPlatform.windows => 'Vixeo Windows',
      _ => 'Vixeo',
    };
  }
}

/// Layout decisions for the current screen.
///
/// TV designs are drawn at 1920×1080: use [tv] to convert a design size into
/// logical pixels (a 1080p TV is usually 960 dp wide, so sizes are halved there).
@immutable
class Layout {
  const Layout._(this.formFactor, this.width, this.scale);

  factory Layout.forWidth(double width, {bool isTv = false}) {
    if (isTv || width >= 1200) {
      return Layout._(FormFactor.large, width, (width / 1920).clamp(0.45, 1.25).toDouble());
    }
    if (width >= 600) {
      return Layout._(FormFactor.tablet, width, 1);
    }
    return Layout._(FormFactor.phone, width, 1);
  }

  static Layout of(BuildContext context) => Layout.forWidth(MediaQuery.sizeOf(context).width, isTv: DeviceInfo.isTv);

  final FormFactor formFactor;
  final double width;

  /// Design pixels → logical pixels, for [FormFactor.large] layouts.
  final double scale;

  bool get isPhone => formFactor == FormFactor.phone;
  bool get isLarge => formFactor == FormFactor.large;
  bool get hasSideRail => formFactor != FormFactor.phone;

  /// Convert a size from the 1920×1080 TV design.
  double tv(double designPx) => designPx * scale;

  /// Horizontal page padding.
  double get gutter => switch (formFactor) {
    FormFactor.phone => 20,
    FormFactor.tablet => 32,
    FormFactor.large => tv(96),
  };
}
