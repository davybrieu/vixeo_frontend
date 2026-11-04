import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../auth/models.dart';
import '../auth/session.dart';

/// An avatar of `GET /avatars`: a 12×12 pixel-art grid, or an image.
class AvatarDef {
  const AvatarDef({
    required this.id,
    required this.name,
    required this.background,
    this.imageUrl,
    this.pixels = const [],
    this.palette = const {},
  });

  factory AvatarDef.fromJson(Map<String, dynamic> json) => AvatarDef(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    background: parseHexColor(json['background'] as String?) ?? VxColors.surfaceHigh,
    imageUrl: json['image_url'] as String?,
    pixels: (json['pixels'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    palette: {
      for (final entry in ((json['palette'] as Map?) ?? const {}).entries)
        entry.key.toString(): ?parseHexColor(entry.value?.toString()),
    },
  );

  final String id;
  final String name;
  final Color background;
  final String? imageUrl;

  /// Rows, top to bottom; each character is a [palette] key, "." is transparent.
  final List<String> pixels;
  final Map<String, Color> palette;
}

/// A license (franchise) and its avatars, already sorted by the API.
class AvatarLicense {
  const AvatarLicense({required this.id, required this.name, required this.avatars});

  factory AvatarLicense.fromJson(Map<String, dynamic> json) => AvatarLicense(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    avatars: ((json['avatars'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AvatarDef.fromJson)
        .toList(),
  );

  final String id;
  final String name;
  final List<AvatarDef> avatars;
}

Color? parseHexColor(String? value) {
  if (value == null) return null;
  final hex = value.replaceFirst('#', '');
  if (hex.length != 6) return null;
  final rgb = int.tryParse(hex, radix: 16);
  return rgb == null ? null : Color(0xFF000000 | rgb);
}

/// Avatar catalog, loaded once per session.
final avatarCatalogProvider = FutureProvider<List<AvatarLicense>>((ref) async {
  ref.watch(sessionProvider.select((s) => s.token));
  final json = await ref.read(apiClientProvider).get('/avatars');
  return ((json['data'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(AvatarLicense.fromJson).toList();
});

/// Avatar by id, null while loading or if unknown.
final avatarByIdProvider = Provider.family<AvatarDef?, String?>((ref, id) {
  if (id == null) return null;
  final licenses = ref.watch(avatarCatalogProvider).value ?? const <AvatarLicense>[];
  for (final license in licenses) {
    for (final avatar in license.avatars) {
      if (avatar.id == id) return avatar;
    }
  }
  return null;
});

/// Draws a pixel-art avatar, crisp at any size.
class PixelAvatarPainter extends CustomPainter {
  const PixelAvatarPainter(this.avatar);

  final AvatarDef avatar;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = avatar.pixels;
    if (rows.isEmpty) return;
    final columns = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    // 15 % margin around the sprite.
    final cell = (size.shortestSide * 0.7) / (columns > rows.length ? columns : rows.length);
    final left = (size.width - cell * columns) / 2;
    final top = (size.height - cell * rows.length) / 2;
    final paint = Paint()..isAntiAlias = false;

    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      for (var x = 0; x < row.length; x++) {
        final color = avatar.palette[row[x]];
        if (color == null) continue;
        paint.color = color;
        // +0.5 px overlap: no hairline gaps between cells.
        canvas.drawRect(Rect.fromLTWH(left + x * cell, top + y * cell, cell + 0.5, cell + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(PixelAvatarPainter oldDelegate) => oldDelegate.avatar != avatar;
}

/// Square avatar tile: the chosen avatar, or the initial on a color.
class AvatarTile extends ConsumerWidget {
  const AvatarTile({
    super.key,
    required this.avatarId,
    required this.initial,
    required this.size,
    this.fallbackColor = VxColors.accent,
    this.fallbackInk = VxColors.onAccent,
    this.radius,
  });

  final String? avatarId;
  final String initial;
  final double size;
  final Color fallbackColor;
  final Color fallbackInk;
  final double? radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatar = ref.watch(avatarByIdProvider(avatarId));
    final r = BorderRadius.circular(radius ?? size * 0.22);
    if (avatar == null) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: fallbackColor, borderRadius: r),
        child: Text(
          initial,
          style: VxText.title(size * 0.42, weight: FontWeight.w800, color: fallbackInk),
        ),
      );
    }
    return ClipRRect(
      borderRadius: r,
      child: SizedBox.square(
        dimension: size,
        child: avatar.imageUrl != null
            ? NetImage(url: avatar.imageUrl, seed: avatar.id.hashCode)
            : ColoredBox(
                color: avatar.background,
                child: CustomPaint(painter: PixelAvatarPainter(avatar)),
              ),
      ),
    );
  }
}

/// Avatar of a profile.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.profile, required this.size, this.radius});

  final Profile? profile;
  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) =>
      AvatarTile(avatarId: profile?.avatar, initial: profile?.initial ?? '?', size: size, radius: radius);
}
