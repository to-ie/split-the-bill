import 'package:flutter/material.dart';

import '../../app.dart';
import '../../ocr/engine_factory.dart';
import '../../ocr/ocr_engine.dart';
import '../../parsing/receipt_parser.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../camera/capture.dart';
import '../widgets/common.dart';
import '../widgets/screen_scaffold.dart';
import 'check_screen.dart';

/// Step 3 of 6. The only screen that touches the camera, and it does so
/// through [CameraController2] rather than the plugin.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  // Only runs while a scan is in flight. A permanently repeating controller
  // would keep the screen awake for nothing.
  late final AnimationController _scanline = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  final CameraController2 _camera = CameraController2();
  OcrEngine? _engine;
  bool _scanning = false;

  /// What to tell the user, and whether they can do something about it.
  String? _error;
  bool _needsPermission = false;
  bool _permissionBlocked = false;

  @override
  void initState() {
    super.initState();
    _engine = createOcrEngine();
    _start();
  }

  Future<void> _start() async {
    if (!cameraAvailable) return;

    final access = await requestCameraAccess();
    if (!mounted) return;

    if (access != CameraAccess.granted) {
      setState(() {
        _needsPermission = true;
        _permissionBlocked = access == CameraAccess.permanentlyDenied;
      });
      return;
    }

    await _camera.initialise();
    if (!mounted) return;
    setState(() {
      _needsPermission = false;
      _error = _camera.lastError;
    });
  }

  @override
  void dispose() {
    _scanline.dispose();
    _camera.dispose();
    _engine?.dispose();
    super.dispose();
  }

  /// Reads the image at [imagePath] and moves on to the correction screen.
  ///
  /// Every failure here used to collapse into one "try again in better light"
  /// message, including failures that had nothing to do with the light: a
  /// camera that never started returned no path at all, and the empty path
  /// was handed to the recogniser, which threw. Each stage now reports
  /// itself.
  Future<void> _read(String? imagePath) async {
    if (_scanning) return;

    if (imagePath == null || imagePath.isEmpty) {
      setState(() => _error = 'No photo to read.');
      return;
    }

    setState(() {
      _scanning = true;
      _error = null;
    });
    _scanline.repeat(reverse: true);

    final app = AppScope.read(context);
    try {
      final result = await _engine!.recognise(imagePath);

      // The text is out; the photograph has done its job. Keeping it would
      // leave a picture of the receipt on the phone for good.
      await app.discardScannedPhoto(imagePath);

      if (result.words.isEmpty) {
        if (!mounted) return;
        _scanline.stop();
        setState(() {
          _scanning = false;
          _error =
              'No text found in that photo. Fill the frame with the '
              'receipt and try again in better light.';
        });
        return;
      }

      final parsed = parseReceipt(result);
      if (!mounted) return;
      _scanline.stop();

      app.applyParse(
        parsed,
        billName: app.draft!.receipt.name.isEmpty
            ? guessBillName(parsed.lines.map((l) => l.description).toList())
            : null,
      );
      Navigator.of(context).pushReplacement(fadeUpRoute(const CheckScreen()));
    } catch (e) {
      await app.discardScannedPhoto(imagePath);
      if (!mounted) return;
      _scanline.stop();
      setState(() {
        _scanning = false;
        // The real message, not a guess about the lighting. Without this
        // there is no way to tell a permission problem from a broken model.
        _error = 'Reading the photo failed.\n$e';
      });
    }
  }

  Future<void> _shoot() async {
    try {
      final path = await _camera.capture();
      await _read(path);
    } on CaptureException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _fromGallery() async {
    try {
      final path = await pickFromGallery();
      if (path == null) {
        // The user backed out of the picker. Not an error.
        if (!cameraAvailable) await _read('sample');
        return;
      }
      await _read(path);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not open that photo.\n$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    final app = AppScope.of(context);
    final group = app.groupById(app.draft?.groupId);
    final destTag = group == null ? '' : ' · ${group.name}';

    return ScreenScaffold(
      title: 'Scan the bill',
      subtitle: 'Step 3 of 6$destTag',
      discardable: true,
      scrollable: false,
      bodyPadding: const EdgeInsets.fromLTRB(R.pad, 12, R.pad, 0),
      body: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 300),
                color: Brand.viewfinder,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreviewArea(
                      controller: _camera,
                      placeholder: _needsPermission
                          ? _PermissionPanel(
                              blocked: _permissionBlocked,
                              onGrant: _start,
                              onOpenSettings: openAppSettingsPage,
                            )
                          : const _ReceiptPlaceholder(),
                    ),
                    const _CornerBrackets(),
                    if (_scanning)
                      AnimatedBuilder(
                        animation: _scanline,
                        builder: (context, _) {
                          // The prototype sweeps the line from 8% to 86% of
                          // the viewfinder height. Alignment runs -1 to 1.
                          final t = 0.08 + 0.78 * _scanline.value;
                          return Align(
                            alignment: Alignment(0, -1 + 2 * t),
                            child: FractionallySizedBox(
                              widthFactor: 0.84,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: Brand.scanline,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Brand.scanline,
                                      blurRadius: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    if (_scanning)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 22),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Brand.green.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(R.pill),
                            ),
                            child: Text(
                              'Reading receipt on-device…',
                              style: ui(12.5, 800, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: c.errorTint,
                borderRadius: BorderRadius.circular(R.small),
              ),
              // Selectable so the text of a real failure can be copied out
              // and reported, rather than retyped from a photo of a screen.
              child: SelectableText(
                _error!,
                textAlign: TextAlign.center,
                style: ui(12, 700, color: c.errorFg, height: 1.4),
              ),
            )
          else
            Text(
              hasRealOcr
                  ? 'OCR runs on the phone. Nothing is uploaded.'
                  : 'Browser preview · no camera here. '
                        'Tap to load a sample receipt.',
              textAlign: TextAlign.center,
              style: ui(12, 700, color: c.muted),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 24),
            // Flexible gaps rather than fixed ones, so the shutter stays
            // centred and nothing is pushed off a narrow screen.
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    child: _GalleryButton(
                      enabled: !_scanning,
                      onTap: _fromGallery,
                    ),
                  ),
                ),
                _Shutter(busy: _scanning, onTap: _shoot),
                const Expanded(child: SizedBox(height: 46)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The first line with letters is usually the shop name.
String guessBillName(List<String> descriptions) {
  for (final d in descriptions) {
    final t = d.trim();
    if (t.length >= 3 && RegExp(r'[A-Za-z]').hasMatch(t)) {
      return t
          .split(' ')
          .map(
            (w) => w.isEmpty
                ? w
                : w[0].toUpperCase() + w.substring(1).toLowerCase(),
          )
          .join(' ');
    }
  }
  return 'New bill';
}

class _GalleryButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool enabled;
  const _GalleryButton({required this.onTap, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Semantics(
      button: true,
      label: 'Choose a photo from the gallery',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.chip,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.image_outlined, size: 20, color: c.muted),
            ),
            const SizedBox(height: 6),
            Text(
              'Gallery',
              style: ui(12, 800, color: c.muted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 76px ring with a 58px green core, per the prototype.
class _Shutter extends StatelessWidget {
  final VoidCallback onTap;
  final bool busy;
  const _Shutter({required this.onTap, required this.busy});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Take a photo of the receipt',
    child: GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Brand.green, width: 4),
        ),
        child: Center(
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: busy ? Brand.green.withValues(alpha: 0.55) : Brand.green,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
        ),
      ),
    ),
  );
}

/// Shown inside the viewfinder when the camera has been refused. A scan
/// screen that simply fails is impossible to recover from; this says what is
/// wrong and offers the one action that fixes it.
class _PermissionPanel extends StatelessWidget {
  final bool blocked;
  final VoidCallback onGrant;
  final Future<void> Function() onOpenSettings;

  const _PermissionPanel({
    required this.blocked,
    required this.onGrant,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.photo_camera_outlined,
            size: 38,
            color: Colors.white54,
          ),
          const SizedBox(height: 14),
          Text(
            blocked
                ? 'Split the Bill needs the camera to read a receipt. '
                      'Camera access '
                      'is turned off for this app.'
                : 'Split the Bill needs the camera to read a receipt.',
            textAlign: TextAlign.center,
            style: ui(13.5, 700, color: Colors.white, height: 1.45),
          ),
          const SizedBox(height: 6),
          Text(
            'The photo is read on this phone and never uploaded.',
            textAlign: TextAlign.center,
            style: ui(11.5, 600, color: Colors.white60, height: 1.4),
          ),
          const SizedBox(height: 16),
          Material(
            color: Brand.green,
            borderRadius: BorderRadius.circular(R.small),
            child: InkWell(
              onTap: blocked ? () => onOpenSettings() : onGrant,
              borderRadius: BorderRadius.circular(R.small),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Text(
                  blocked ? 'Open app settings' : 'Allow the camera',
                  style: ui(14, 800, color: Colors.white),
                ),
              ),
            ),
          ),
          if (blocked) ...[
            const SizedBox(height: 10),
            Text(
              'Permissions › Camera › Allow',
              style: ui(11.5, 600, color: Colors.white54),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The striped, slightly rotated receipt stand-in, shown wherever there is
/// no camera.
class _ReceiptPlaceholder extends StatelessWidget {
  const _ReceiptPlaceholder();

  @override
  Widget build(BuildContext context) => Center(
    child: Transform.rotate(
      angle: -3 * 3.1415926 / 180,
      child: Container(
        width: 190,
        height: 310,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(
              color: Color(0x80000000),
              blurRadius: 40,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                tileMode: TileMode.repeated,
                colors: [
                  Color(0xFFF4F1E8),
                  Color(0xFFF4F1E8),
                  Color(0xFFE7E2D3),
                  Color(0xFFE7E2D3),
                ],
                // 26px light, 5px dark, over a 31px tile.
                stops: [0.0, 0.839, 0.839, 1.0],
              ),
            ),
            child: SizedBox.expand(),
          ),
        ),
      ),
    ),
  );
}

class _CornerBrackets extends StatelessWidget {
  const _CornerBrackets();

  @override
  Widget build(BuildContext context) {
    Widget corner(
      Alignment alignment,
      BorderSide? top,
      BorderSide? bottom,
      BorderSide? left,
      BorderSide? right,
      BorderRadius radius,
    ) => Align(
      alignment: alignment,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          border: Border(
            top: top ?? BorderSide.none,
            bottom: bottom ?? BorderSide.none,
            left: left ?? BorderSide.none,
            right: right ?? BorderSide.none,
          ),
          borderRadius: radius,
        ),
      ),
    );

    const side = BorderSide(color: Brand.green, width: 3);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Stack(
        children: [
          corner(
            Alignment.topLeft,
            side,
            null,
            side,
            null,
            const BorderRadius.only(topLeft: Radius.circular(8)),
          ),
          corner(
            Alignment.topRight,
            side,
            null,
            null,
            side,
            const BorderRadius.only(topRight: Radius.circular(8)),
          ),
          corner(
            Alignment.bottomLeft,
            null,
            side,
            side,
            null,
            const BorderRadius.only(bottomLeft: Radius.circular(8)),
          ),
          corner(
            Alignment.bottomRight,
            null,
            side,
            null,
            side,
            const BorderRadius.only(bottomRight: Radius.circular(8)),
          ),
        ],
      ),
    );
  }
}
