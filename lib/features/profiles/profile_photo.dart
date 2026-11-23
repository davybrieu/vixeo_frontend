import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/design.dart';
import '../../core/device/layout.dart';
import '../../core/theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/page_header.dart';

// The profile's own photo, instead of its avatar (demande du développeur, 23/11/2026; API:
// vixeo_backend/docs/social.md): chosen on the device, framed on « Cadrer la photo », sent by
// « Modifier le profil » as a square PNG. The API keeps the central square, 512 pixels, re-encoded.

/// Side of the square sent to the API, in pixels (the size it keeps).
const profilePhotoSide = 512;

/// Largest photo file read, in bytes.
const maxProfilePhotoBytes = 40 * 1024 * 1024;

/// Whether a photo can be chosen here: not on a TV (no files to browse with a remote).
bool get canChooseProfilePhoto => !DeviceInfo.isTv;

/// « Importer une photo »: a photo of the device, then « Cadrer la photo ». The framed square (PNG,
/// [profilePhotoSide] pixels), or null when nothing was chosen.
Future<Uint8List?> chooseProfilePhoto(BuildContext context) async {
  final file = await FilePicker.pickFile(type: FileType.image);
  if (file == null || !context.mounted) return null;
  final length = file.lengthSync() ?? await file.length() ?? 0;
  if (!context.mounted) return null;
  if (length <= 0 || length > maxProfilePhotoBytes) {
    showVxSnack(
      context,
      length <= 0 ? 'Cette image ne peut pas être lue.' : 'Cette photo est trop lourde (40 Mo au plus).',
      icon: Icons.error_outline_rounded,
    );
    return null;
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.readAsByteStream()) {
    bytes.add(chunk);
  }
  if (!context.mounted) return null;
  return framePhoto(context, bytes.takeBytes());
}

/// « Cadrer la photo » over the current page: the framed square, or null when it is left.
Future<Uint8List?> framePhoto(BuildContext context, Uint8List bytes) => Navigator.of(
  context,
  rootNavigator: true,
).push<Uint8List>(MaterialPageRoute(builder: (_) => PhotoFramingScreen(bytes: bytes)));

/// « Cadrer la photo »: the photo fills a square with a round guide (the avatars are round); it is
/// moved with a finger or the mouse and zoomed (pinch, mouse wheel, « Zoomer » / « Dézoomer »).
/// « Utiliser cette photo » gives back the square, [profilePhotoSide] pixels, as PNG.
class PhotoFramingScreen extends StatefulWidget {
  const PhotoFramingScreen({super.key, required this.bytes});

  final Uint8List bytes;

  /// Largest side the photo is decoded at: a 50-megapixel photo would fill the memory, and the
  /// square sent is 512 pixels.
  static const maxDecodedSide = 2048;

  /// Most zoom, from the photo filling the square.
  static const maxZoom = 6.0;

  @override
  State<PhotoFramingScreen> createState() => _PhotoFramingScreenState();
}

class _PhotoFramingScreenState extends State<PhotoFramingScreen> {
  final _transform = TransformationController();
  ui.Image? _image;
  bool _failed = false;
  bool _saving = false;

  /// Side of the square on the screen, the photo centered in it when it changes.
  double _side = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_decode());
  }

  @override
  void dispose() {
    _transform.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(widget.bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          final longest = math.max(width, height);
          if (longest <= PhotoFramingScreen.maxDecodedSide) return ui.TargetImageSize();
          // The width only: the decoder keeps the proportions (and turns the photo upright).
          return ui.TargetImageSize(width: (width * PhotoFramingScreen.maxDecodedSide / longest).round());
        },
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// How much the photo is enlarged to fill the square, before any zoom.
  double _cover(ui.Image image) => _side / math.min(image.width, image.height);

  /// Zoom [scale], moved by ([dx], [dy]), kept inside the photo: the square is always filled.
  Matrix4 _framed(ui.Image image, double scale, double dx, double dy) {
    final cover = _cover(image);
    final width = image.width * cover * scale;
    final height = image.height * cover * scale;
    return Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(dx.clamp(_side - width, 0).toDouble(), dy.clamp(_side - height, 0).toDouble(), 0);
  }

  /// The photo centered, filling the square.
  void _center(ui.Image image) {
    final cover = _cover(image);
    _transform.value = _framed(image, 1, (_side - image.width * cover) / 2, (_side - image.height * cover) / 2);
  }

  /// « Zoomer » / « Dézoomer »: around the middle of the square.
  void _zoom(double factor) {
    final image = _image;
    if (image == null) return;
    final storage = _transform.value.storage;
    final scale = storage[0];
    final next = (scale * factor).clamp(1.0, PhotoFramingScreen.maxZoom).toDouble();
    final ratio = next / scale;
    final middle = _side / 2;
    _transform.value = _framed(
      image,
      next,
      middle - (middle - storage[12]) * ratio,
      middle - (middle - storage[13]) * ratio,
    );
  }

  Future<void> _use() async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final storage = _transform.value.storage;
      // From the screen back to the photo's pixels: what the square shows.
      final scale = storage[0] * _cover(image);
      final side = math.min(_side / scale, math.min(image.width, image.height).toDouble());
      final left = (-storage[12] / scale).clamp(0.0, image.width - side).toDouble();
      final top = (-storage[13] / scale).clamp(0.0, image.height - side).toDouble();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        Rect.fromLTWH(left, top, side, side),
        Rect.fromLTWH(0, 0, profilePhotoSide.toDouble(), profilePhotoSide.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final square = await picture.toImage(profilePhotoSide, profilePhotoSide);
      picture.dispose();
      final data = await square.toByteData(format: ui.ImageByteFormat.png);
      square.dispose();
      if (!mounted) return;
      if (data == null) throw StateError('png');
      Navigator.of(context).pop(data.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showVxSnack(context, 'La photo n’a pas pu être préparée.', icon: Icons.error_outline_rounded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final image = _image;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const VxPageHeader(title: 'Cadrer la photo', back: true),
            Expanded(
              child: _failed
                  ? const EmptyState(
                      icon: Icons.broken_image_outlined,
                      title: 'Impossible d’ouvrir cette image',
                      message: 'Choisissez une autre photo.',
                    )
                  : image == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // The square, and under it the hint, the zoom buttons and « Utiliser ».
                        final controls = layout.size(220, tv: 300);
                        final side = math.max(
                          120.0,
                          math.min(
                            math.min(constraints.maxWidth - 2 * layout.gutter, constraints.maxHeight - controls),
                            layout.size(480, tv: 640),
                          ),
                        );
                        if (side != _side) {
                          _side = side;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _center(image);
                          });
                        }
                        return Center(child: _frame(layout, image, side));
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame(Layout layout, ui.Image image, double side) {
    final cover = side / math.min(image.width, image.height);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: side,
          child: Stack(
            children: [
              Semantics(
                label: 'Photo à cadrer : déplacez-la et zoomez',
                child: InteractiveViewer(
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: PhotoFramingScreen.maxZoom,
                  boundaryMargin: EdgeInsets.zero,
                  constrained: false,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: image.width * cover,
                    height: image.height * cover,
                    child: RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                  ),
                ),
              ),
              // What the round avatars will show; the corners are cut there.
              const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _RoundGuide()))),
            ],
          ),
        ),
        SizedBox(height: layout.space(VxSpace.m)),
        Text(
          'Déplacez la photo et zoomez pour la cadrer.',
          textAlign: TextAlign.center,
          style: VxText.body(layout.size(14, tv: 20), color: VxColors.textSecondary),
        ),
        SizedBox(height: layout.space(VxSpace.s)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            VxIconAction(icon: Icons.zoom_out_rounded, label: 'Dézoomer', onPressed: () => _zoom(1 / 1.25)),
            SizedBox(width: layout.space(VxSpace.m)),
            VxIconAction(icon: Icons.zoom_in_rounded, label: 'Zoomer', onPressed: () => _zoom(1.25)),
          ],
        ),
        SizedBox(height: layout.space(VxSpace.m)),
        SizedBox(
          width: side,
          child: VxButton(
            label: 'Utiliser cette photo',
            icon: Icons.check_rounded,
            expand: true,
            autofocus: true,
            loading: _saving,
            onPressed: _use,
          ),
        ),
      ],
    );
  }
}

/// A darker veil outside the circle, and its outline.
class _RoundGuide extends CustomPainter {
  const _RoundGuide();

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(circle)
        ..addOval(circle),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawOval(
      circle.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_RoundGuide oldDelegate) => false;
}
