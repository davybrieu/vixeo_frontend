import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'device/layout.dart';
import 'widgets/common.dart';

/// Sends a link with the system's share sheet (« Partager » of a profile). Android: the chooser
/// of Android (`app.vixeo/share` in MainActivity.kt). Elsewhere (Windows, or when it fails): the
/// link is copied and a message says so.
class LinkSharer {
  const LinkSharer();

  static const _channel = MethodChannel('app.vixeo/share');

  /// True when the share sheet opened.
  Future<bool> share({required String text, String? subject}) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('share', {'text': text, 'subject': ?subject}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

extension ImageSharing on LinkSharer {
  /// Opens the share sheet with a PNG of the app's cache (`cache/shared/`); false elsewhere.
  Future<bool> shareImage(String path, {String? text}) async {
    if (!Platform.isAndroid) return false;
    try {
      return await LinkSharer._channel.invokeMethod<bool>('shareImage', {'path': path, 'text': ?text}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

final linkSharerProvider = Provider<LinkSharer>((ref) => const LinkSharer());

/// Whether a share button makes sense here: not on a TV (no share sheet, nothing to paste into).
bool get canShareLinks => !DeviceInfo.isTv;

/// « Partager » a link: the share sheet, else the link copied (« Lien copié »).
Future<void> shareLink(WidgetRef ref, BuildContext context, {required String url, String? message, String? subject}) async {
  final text = message == null ? url : '$message\n$url';
  if (await ref.read(linkSharerProvider).share(text: text, subject: subject)) return;
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) showVxSnack(context, 'Lien copié', icon: Icons.link_rounded);
}
