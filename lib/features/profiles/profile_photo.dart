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

// The profile's own photo, instead of its avatar (demande du développeur, 23/11/2026), and its own
// cover, instead of a cover of the catalog (24/11/2026; API: vixeo_backend/docs/social.md): chosen
// on the device, framed on « Cadrer la photo » / « Cadrer la couverture », sent by « Modifier le
// profil » as a PNG. The API keeps the central part with the same shape, re-encoded.

/// Side of the square sent to the API, in pixels (the size it keeps).
const profilePhotoSide = 512;

/// Largest image file read, in bytes.
const maxProfilePhotoBytes = 40 * 1024 * 1024;

/// Whether an image can be chosen here: not on a TV (no files to browse with a remote).
bool get canChooseProfilePhoto => !DeviceInfo.isTv;

/// What is framed: its shape, the size sent to the API and the page's words.
enum FramingShape {
  /// The profile photo: a square with a round guide (the avatars are round), 512 pixels.
  photo('Cadrer la photo', 'Utiliser cette photo', 1, profilePhotoSide, profilePhotoSide),

  /// The cover of the profile page: a 3:1 banner, 1,500 × 500 pixels.
  cover('Cadrer la couverture', 'Utiliser cette image', 3, 1500, 500);

  const FramingShape(this.title, this.useLabel, this.aspectRatio, this.width, this.height);

  final String title;
  final String useLabel;

  /// Width over height.
  final double aspectRatio;

  /// Size of the PNG sent, in pixels.
  final int width;
  final int height;
}

/// « Importer une photo »: a photo of the device, then « Cadrer la photo ». The framed square (PNG,
/// [profilePhotoSide] pixels), or null when nothing was chosen.
Future<Uint8List?> chooseProfilePhoto(BuildContext context) => chooseProfileImage(context, FramingShape.photo);

/// An image of the device, then its framing page ([shape]). The framed PNG, or null when nothing
/// was chosen.
Future<Uint8List?> chooseProfileImage(BuildContext context, FramingShape shape) async {
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
  return framePhoto(context, bytes.takeBytes(), shape: shape);
}

/// The framing page ([shape]) over the current page: the framed PNG, or null when it is left.
Future<Uint8List?> framePhoto(BuildContext context, Uint8List bytes, {FramingShape shape = FramingShape.photo}) =>
    Navigator.of(
      context,
      rootNavigator: true,
    ).push<Uint8List>(MaterialPageRoute(builder: (_) => PhotoFramingScreen(bytes: bytes, shape: shape)));

/// « Cadrer la photo » (or « Cadrer la couverture »): the image fills the frame of [shape] (a
/// square with a round guide, or a 3:1 banner); it is moved with a finger or the mouse and zoomed
/// (pinch, mouse wheel, « Zoomer » / « Dézoomer »). « Utiliser cette photo » gives back what the
/// frame shows, at the size of [shape], as PNG.
class PhotoFramingScreen extends StatefulWidget {
  const PhotoFramingScreen({super.key, required this.bytes, this.shape = FramingShape.photo});

  final Uint8List bytes;
  final FramingShape shape;

  /// Largest side the image is decoded at: a 50-megapixel photo would fill the memory, and what is
  /// sent is 1,500 pixels wide at most.
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

  /// Size of the frame on the screen, the image centered in it when it changes.
  double _frameWidth = 0;
  double _frameHeight = 0;

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

  /// How much the image is enlarged to fill the frame, before any zoom.
  double _cover(ui.Image image) => _coverOf(image, _frameWidth, _frameHeight);

  static double _coverOf(ui.Image image, double width, double height) =>
      math.max(width / image.width, height / image.height);

  /// Zoom [scale], moved by ([dx], [dy]), kept inside the image: the frame is always filled.
  Matrix4 _framed(ui.Image image, double scale, double dx, double dy) {
    final cover = _cover(image);
    final width = image.width * cover * scale;
    final height = image.height * cover * scale;
    return Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(
        dx.clamp(_frameWidth - width, 0).toDouble(),
        dy.clamp(_frameHeight - height, 0).toDouble(),
        0,
      );
  }

  /// The image centered, filling the frame.
  void _center(ui.Image image) {
    final cover = _cover(image);
    _transform.value = _framed(
      image,
      1,
      (_frameWidth - image.width * cover) / 2,
      (_frameHeight - image.height * cover) / 2,
    );
  }

  /// « Zoomer » / « Dézoomer »: around the middle of the frame.
  void _zoom(double factor) {
    final image = _image;
    if (image == null) return;
    final storage = _transform.value.storage;
    final scale = storage[0];
    final next = (scale * factor).clamp(1.0, PhotoFramingScreen.maxZoom).toDouble();
    final ratio = next / scale;
    final middleX = _frameWidth / 2;
    final middleY = _frameHeight / 2;
    _transform.value = _framed(
      image,
      next,
      middleX - (middleX - storage[12]) * ratio,
      middleY - (middleY - storage[13]) * ratio,
    );
  }

  Future<void> _use() async {
    final image = _image;
    if (image == null || _saving) return;
    setState(() => _saving = true);
    try {
      final storage = _transform.value.storage;
      final shape = widget.shape;
      // From the screen back to the image's pixels: what the frame shows.
      final scale = storage[0] * _cover(image);
      final width = math.min(_frameWidth / scale, image.width.toDouble());
      final height = math.min(_frameHeight / scale, image.height.toDouble());
      final left = (-storage[12] / scale).clamp(0.0, image.width - width).toDouble();
      final top = (-storage[13] / scale).clamp(0.0, image.height - height).toDouble();
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        Rect.fromLTWH(left, top, width, height),
        Rect.fromLTWH(0, 0, shape.width.toDouble(), shape.height.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      final framed = await picture.toImage(shape.width, shape.height);
      picture.dispose();
      final data = await framed.toByteData(format: ui.ImageByteFormat.png);
      framed.dispose();
      if (!mounted) return;
      if (data == null) throw StateError('png');
      Navigator.of(context).pop(data.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showVxSnack(context, 'L’image n’a pas pu être préparée.', icon: Icons.error_outline_rounded);
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
            VxPageHeader(title: widget.shape.title, back: true),
            Expanded(
              child: _failed
                  ? const EmptyState(
                      icon: Icons.broken_image_outlined,
                      title: 'Impossible d’ouvrir cette image',
                      message: 'Choisissez une autre image.',
                    )
                  : image == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // The frame, and under it the hint, the zoom buttons and « Utiliser ».
                        final controls = layout.size(220, tv: 300);
                        final aspect = widget.shape.aspectRatio;
                        final largest = aspect > 1 ? layout.size(720, tv: 1200) : layout.size(480, tv: 640);
                        final width = math.max(
                          120.0,
                          math.min(
                            math.min(constraints.maxWidth - 2 * layout.gutter, (constraints.maxHeight - controls) * aspect),
                            largest,
                          ),
                        );
                        final height = width / aspect;
                        if (width != _frameWidth || height != _frameHeight) {
                          _frameWidth = width;
                          _frameHeight = height;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _center(image);
                          });
                        }
                        return Center(child: _frame(layout, image, width, height));
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame(Layout layout, ui.Image image, double width, double height) {
    final cover = _coverOf(image, width, height);
    final photo = widget.shape == FramingShape.photo;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Semantics(
                label: photo ? 'Photo à cadrer : déplacez-la et zoomez' : 'Image à cadrer : déplacez-la et zoomez',
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
              // What the round avatars will show (the corners are cut there); a cover: its outline.
              Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _FrameGuide(round: photo)))),
            ],
          ),
        ),
        SizedBox(height: layout.space(VxSpace.m)),
        Text(
          photo ? 'Déplacez la photo et zoomez pour la cadrer.' : 'Déplacez l’image et zoomez pour la cadrer.',
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
          width: math.min(width, layout.size(480, tv: 640)),
          child: VxButton(
            label: widget.shape.useLabel,
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

/// A photo: a darker veil outside the circle, and its outline. A cover: the outline of the frame.
class _FrameGuide extends CustomPainter {
  const _FrameGuide({required this.round});

  final bool round;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(0, 0, size.width, size.height);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.85);
    if (!round) {
      canvas.drawRect(frame.deflate(1), outline);
      return;
    }
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(frame)
        ..addOval(frame),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawOval(frame.deflate(1), outline);
  }

  @override
  bool shouldRepaint(_FrameGuide oldDelegate) => oldDelegate.round != round;
}
