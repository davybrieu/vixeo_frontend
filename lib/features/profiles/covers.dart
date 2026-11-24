import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../auth/session.dart';
import 'avatars.dart' show parseHexColor;

// The cover of a profile, the 3:1 banner at the top of its page (demande du développeur,
// 24/11/2026; API: vixeo_backend/docs/social.md): a cover of the catalog (`GET /covers`, several
// styles, one at random for a new profile) or its own image (`cover_url`). A cover of the catalog
// is not an image: a pattern and its colors, drawn here by [CoverPainter] (like the pixel-art
// avatars), so nothing is downloaded and it is sharp at any size.
//
// Flutter: a `CustomPainter` draws on a canvas, like the 2D canvas of a web page (gradients,
// paths, circles). `ProfileCover` is the widget to put anywhere a cover is shown.

/// Width over height of a cover.
const coverAspectRatio = 3.0;

/// How a cover of the catalog is drawn (`pattern` of the API).
enum CoverPattern {
  linear,
  glow,
  stripes,
  dots,
  waves,
  grid,
  film,
  spotlight,
  curtain,
  stars;

  /// A pattern this version doesn't know: a gradient of its colors.
  static CoverPattern parse(Object? value) =>
      CoverPattern.values.firstWhere((p) => p.name == value, orElse: () => CoverPattern.linear);
}

/// A cover of `GET /covers`.
class CoverDef {
  const CoverDef({
    required this.id,
    required this.name,
    required this.pattern,
    required this.colors,
    this.angle = 135,
  });

  factory CoverDef.fromJson(Map<String, dynamic> json) {
    final colors = [
      for (final value in (json['colors'] as List?) ?? const []) ?parseHexColor(value?.toString()),
    ];
    return CoverDef(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      pattern: CoverPattern.parse(json['pattern']),
      colors: colors.isEmpty ? fallback.colors : colors,
      angle: (json['angle'] as num?)?.toDouble() ?? 135,
    );
  }

  /// A profile without a cover (an older API), or a cover this version doesn't know: the green of
  /// the app.
  static const fallback = CoverDef(
    id: 'aurore',
    name: 'Aurore',
    pattern: CoverPattern.linear,
    colors: [Color(0xFF03140A), Color(0xFF0E5C3A), Color(0xFF2EE58A)],
    angle: 160,
  );

  final String id;
  final String name;
  final CoverPattern pattern;

  /// In the order the pattern reads them, the background first.
  final List<Color> colors;

  /// Direction of a linear gradient, in degrees: 0 = left to right, 90 = top to bottom.
  final double angle;

  /// The [i]th color, or the last one.
  Color color(int i) => colors[math.min(i, colors.length - 1)];
}

/// A style (« Dégradés », « Lumières », « Motifs », « Cinéma ») and its covers.
class CoverStyle {
  const CoverStyle({required this.id, required this.name, required this.covers});

  factory CoverStyle.fromJson(Map<String, dynamic> json) => CoverStyle(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    covers: ((json['covers'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(CoverDef.fromJson).toList(),
  );

  final String id;
  final String name;
  final List<CoverDef> covers;
}

/// The cover catalog, loaded once per session.
final coverCatalogProvider = FutureProvider<List<CoverStyle>>((ref) async {
  ref.watch(sessionProvider.select((s) => s.token));
  final json = await ref.read(apiClientProvider).get('/covers');
  return ((json['data'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(CoverStyle.fromJson).toList();
});

/// A cover by id: null while the catalog loads; [CoverDef.fallback] for no cover or an unknown one.
final coverByIdProvider = Provider.family<CoverDef?, String?>((ref, id) {
  final styles = ref.watch(coverCatalogProvider).value;
  if (styles == null) return id == null ? CoverDef.fallback : null;
  for (final style in styles) {
    for (final cover in style.covers) {
      if (cover.id == id) return cover;
    }
  }
  return CoverDef.fallback;
});

/// The cover of a profile: its own image ([imageUrl], the cover of the catalog under it while it
/// loads), else the cover [coverId] of the catalog. Fills its box; decorative for screen readers.
class ProfileCover extends ConsumerWidget {
  const ProfileCover({super.key, this.coverId, this.imageUrl, this.borderRadius = 0});

  final String? coverId;
  final String? imageUrl;
  final double borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = ref.watch(coverByIdProvider(coverId));
    final drawn = cover == null
        ? const ColoredBox(color: VxColors.surface)
        : RepaintBoundary(child: CustomPaint(painter: CoverPainter(cover)));
    final url = imageUrl;
    Widget child = url == null || url.isEmpty
        ? drawn
        : LayoutBuilder(
            builder: (context, constraints) => CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              // Decoded at the size shown (the stored image is 1,500 pixels wide).
              memCacheWidth: constraints.maxWidth.isFinite
                  ? ((constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)) / 128).ceil() * 128
                  : null,
              fadeInDuration: const Duration(milliseconds: 200),
              // The cover of the catalog while it loads, or if it can't.
              placeholder: (_, _) => drawn,
              errorWidget: (_, _, _) => drawn,
            ),
          );
    if (borderRadius > 0) {
      child = ClipRRect(borderRadius: BorderRadius.circular(borderRadius), child: child);
    }
    return ExcludeSemantics(child: SizedBox.expand(child: child));
  }
}

/// Draws a cover of the catalog: its pattern with its colors, at any size.
class CoverPainter extends CustomPainter {
  const CoverPainter(this.cover);

  final CoverDef cover;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (cover.pattern) {
      case CoverPattern.linear:
        _linear(canvas, size);
      case CoverPattern.glow:
        _glow(canvas, size);
      case CoverPattern.stripes:
        _stripes(canvas, size);
      case CoverPattern.dots:
        _dots(canvas, size);
      case CoverPattern.waves:
        _waves(canvas, size);
      case CoverPattern.grid:
        _grid(canvas, size);
      case CoverPattern.film:
        _film(canvas, size);
      case CoverPattern.spotlight:
        _spotlight(canvas, size);
      case CoverPattern.curtain:
        _curtain(canvas, size);
      case CoverPattern.stars:
        _stars(canvas, size);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CoverPainter oldDelegate) => oldDelegate.cover != cover;

  Color _c(int i) => cover.color(i);

  static Paint _fill(Color color) => Paint()..color = color;

  /// Evenly spread [colors] from [from] to [to].
  static Paint _gradient(Offset from, Offset to, List<Color> colors, [List<double>? stops]) => Paint()
    ..shader = ui.Gradient.linear(
      from,
      to,
      colors,
      stops ?? [for (var i = 0; i < colors.length; i++) colors.length == 1 ? 0 : i / (colors.length - 1)],
    );

  /// A vertical gradient of [colors] over the whole box.
  static void _vertical(Canvas canvas, Size size, Color top, Color bottom) =>
      canvas.drawRect(Offset.zero & size, _gradient(Offset.zero, Offset(0, size.height), [top, bottom]));

  // Dégradés: the colors along [CoverDef.angle].
  void _linear(Canvas canvas, Size size) {
    final a = cover.angle * math.pi / 180;
    final center = size.center(Offset.zero);
    final half = Offset(math.cos(a) * size.width / 2, math.sin(a) * size.height / 2);
    canvas.drawRect(Offset.zero & size, _gradient(center - half, center + half, cover.colors));
  }

  // Lumières: soft lights (colors 1…) on a background (color 0).
  void _glow(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, _fill(_c(0)));
    const spots = [(0.18, 0.25, 0.55), (0.78, 0.1, 0.5), (0.55, 1.05, 0.6)];
    for (var i = 1; i < cover.colors.length; i++) {
      final (x, y, r) = spots[(i - 1) % spots.length];
      final color = cover.colors[i];
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.radial(Offset(x * w, y * h), r * w, [
            color.withValues(alpha: 0.5),
            color.withValues(alpha: 0),
          ]),
      );
    }
  }

  // Rayures: diagonal stripes, a thin line of color 2 now and then, darker to the right.
  void _stripes(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, _fill(_c(0)));
    final s = h / 5;
    final band = _fill(_c(1));
    final line = Paint()
      ..color = _c(2).withValues(alpha: 0.55)
      ..strokeWidth = math.max(1, h / 90);
    for (var i = -(h / s).ceil() - 1; i * s < w + h; i++) {
      final x = i * s;
      if (i % 2 == 0) {
        canvas.drawPath(
          Path()
            ..moveTo(x, h)
            ..lineTo(x + s, h)
            ..lineTo(x + s + h, 0)
            ..lineTo(x + h, 0)
            ..close(),
          band,
        );
      }
      if (i % 5 == 0) canvas.drawLine(Offset(x, h), Offset(x + h, 0), line);
    }
    canvas.drawRect(
      Offset.zero & size,
      _gradient(Offset.zero, Offset(w, 0), [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.45)]),
    );
  }

  // Points: halftone dots of color 2, growing to the right, on a gradient of colors 0 and 1.
  void _dots(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, _gradient(Offset.zero, Offset(w, h), [_c(0), _c(1)]));
    final s = h / 9;
    final dot = _fill(_c(2).withValues(alpha: 0.55));
    for (var y = s / 2; y < h; y += s) {
      for (var x = s / 2; x < w; x += s) {
        final t = x / w;
        final r = s * 0.42 * t * t;
        if (r >= 0.3) canvas.drawCircle(Offset(x, y), r, dot);
      }
    }
  }

  // Vagues: layered waves (colors 1…) over the background (color 0).
  void _waves(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, _fill(_c(0)));
    for (var i = 0; i < cover.colors.length - 1; i++) {
      final base = h * (0.42 + i * 0.17);
      final amplitude = h * 0.08;
      final length = w / (1.3 + i * 0.4);
      final phase = i * 1.7;
      final path = Path()..moveTo(0, h);
      final step = math.max(2.0, w / 200);
      for (var x = 0.0; x <= w + step; x += step) {
        path.lineTo(x, base + math.sin(x / length * 2 * math.pi + phase) * amplitude);
      }
      path
        ..lineTo(w, h)
        ..close();
      canvas.drawPath(path, _fill(cover.colors[i + 1].withValues(alpha: 0.9)));
    }
  }

  // Rétro: a striped sun (color 2) setting on a perspective grid (color 3), the sky from color 0
  // to color 1.
  void _grid(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizon = h * 0.58;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, horizon),
      _gradient(Offset.zero, Offset(0, horizon), [_c(0), _c(1)]),
    );
    final r = h * 0.36;
    final cx = w / 2;
    final sun = Path()..addOval(Rect.fromCircle(center: Offset(cx, horizon), radius: r));
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, w, horizon));
    canvas.clipPath(sun);
    canvas.drawRect(
      Rect.fromLTWH(cx - r, horizon - r, 2 * r, r),
      _gradient(Offset(0, horizon - r), Offset(0, horizon), [const Color(0xFFFFD36E), _c(2)]),
    );
    // The bands cut in the sun.
    for (var i = 0; i < 5; i++) {
      final y = horizon - r * 0.08 - i * r * 0.17;
      final thickness = r * 0.035 * (5 - i) / 1.5;
      canvas.drawRect(Rect.fromLTWH(cx - r, y - thickness, 2 * r, thickness), _fill(_c(1)));
    }
    canvas.restore();
    canvas.drawRect(Rect.fromLTWH(0, horizon, w, h - horizon), _fill(_c(0)));
    final line = Paint()
      ..color = _c(3).withValues(alpha: 0.85)
      ..strokeWidth = math.max(1, h / 120);
    for (var i = 1; i <= 8; i++) {
      final t = i / 8;
      final y = horizon + (h - horizon) * t * t;
      canvas.drawLine(Offset(0, y), Offset(w, y), line);
    }
    for (var i = -12; i <= 12; i++) {
      canvas.drawLine(Offset(cx + i * w * 0.02, horizon), Offset(cx + i * w * 0.16, h), line);
    }
    canvas.drawLine(Offset(0, horizon), Offset(w, horizon), line..color = _c(3));
  }

  // Pellicule: a film strip (color 1) with its holes, frames lit by color 2.
  void _film(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    canvas.drawRect(Offset.zero & size, _fill(_c(0)));
    final top = h * 0.14;
    final bottom = h * 0.86;
    final band = bottom - top;
    canvas.drawRect(Rect.fromLTWH(0, top, w, band), _fill(_c(1)));
    final hole = band * 0.09;
    final gap = band * 0.06;
    final pitch = hole * 2.2;
    final holes = _fill(_c(0));
    for (var x = pitch * 0.3; x < w; x += pitch) {
      for (final y in [top + gap, bottom - gap - hole]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, hole * 1.3, hole), Radius.circular(hole * 0.25)),
          holes,
        );
      }
    }
    final frameTop = top + gap * 2 + hole;
    final frameHeight = band - 2 * (gap * 2 + hole);
    final frameWidth = frameHeight * 1.5;
    final frameGap = frameHeight * 0.12;
    var i = 0;
    for (var x = frameGap; x < w; x += frameWidth + frameGap, i++) {
      canvas.drawRect(
        Rect.fromLTWH(x, frameTop, frameWidth, frameHeight),
        _gradient(Offset(x, frameTop), Offset(x + frameWidth, frameTop + frameHeight), [
          _c(2).withValues(alpha: 0.45 - 0.05 * (i % 3)),
          _c(2).withValues(alpha: 0.12),
        ]),
      );
    }
  }

  // Projecteurs: beams of light (color 2) rising from the bottom, the night from color 0 to 1.
  void _spotlight(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    _vertical(canvas, size, _c(0), _c(1));
    final light = _c(2);
    const beams = [(0.18, -0.05, 0.32), (0.5, 0.0, 0.4), (0.82, 0.05, 0.32)];
    for (final (x, lean, spread) in beams) {
      final bottom = x * w;
      final top = bottom + lean * w;
      canvas.drawPath(
        Path()
          ..moveTo(bottom - w * 0.012, h)
          ..lineTo(bottom + w * 0.012, h)
          ..lineTo(top + spread * w * 0.5, 0)
          ..lineTo(top - spread * w * 0.5, 0)
          ..close(),
        _gradient(Offset(0, h), Offset.zero, [light.withValues(alpha: 0.38), light.withValues(alpha: 0)]),
      );
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(Offset(w / 2, h), w * 0.5, [
          light.withValues(alpha: 0.25),
          light.withValues(alpha: 0),
        ]),
    );
  }

  // Rideau: the folds of a theater curtain (colors 0 and 1), its valance trimmed with color 2.
  void _curtain(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const folds = 14;
    final fold = w / folds;
    for (var i = 0; i < folds; i++) {
      final x = i * fold;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, fold + 1, h),
        _gradient(Offset(x, 0), Offset(x + fold, 0), [_c(0), _c(1), _c(0)], [0, 0.5, 1]),
      );
    }
    final valance = h * 0.17;
    final scallops = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, valance);
    for (var i = folds - 1; i >= 0; i--) {
      scallops.quadraticBezierTo(i * fold + fold / 2, valance * 1.35, i * fold, valance);
    }
    scallops.close();
    canvas.drawPath(scallops, _gradient(Offset.zero, Offset(0, valance), [_c(0), _c(1)]));
    final trim = Path()..moveTo(0, valance);
    for (var i = 0; i < folds; i++) {
      trim.quadraticBezierTo(i * fold + fold / 2, valance * 1.35, (i + 1) * fold, valance);
    }
    canvas.drawPath(
      trim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, h / 60)
        ..color = _c(2),
    );
    canvas.drawRect(
      Offset.zero & size,
      _gradient(
        Offset.zero,
        Offset(0, h),
        [Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.45)],
        [0.6, 1],
      ),
    );
  }

  // Nuit étoilée: stars (color 2) always at the same places, a faint milky way, the night from
  // color 0 to 1.
  void _stars(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    _vertical(canvas, size, _c(0), _c(1));
    final light = _c(2);
    canvas.drawRect(
      Offset.zero & size,
      _gradient(
        Offset(0, h),
        Offset(w, 0),
        [light.withValues(alpha: 0), light.withValues(alpha: 0.08), light.withValues(alpha: 0)],
        [0.3, 0.5, 0.7],
      ),
    );
    // The same sky every time (a fixed seed).
    var seed = 42;
    double next() {
      seed = (seed * 1103515245 + 12345) % 2147483648;
      return seed / 2147483648;
    }

    final count = (w * h / 900).round();
    for (var i = 0; i < count; i++) {
      final x = next() * w;
      final y = next() * h;
      final radius = (0.4 + next() * 1.1) * h / 160;
      final alpha = 0.3 + next() * 0.7;
      canvas.drawCircle(Offset(x, y), radius, _fill(light.withValues(alpha: alpha)));
    }
  }
}
