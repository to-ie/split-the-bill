import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

bool get cameraAvailable => Platform.isAndroid || Platform.isIOS;

enum CameraAccess { granted, denied, permanentlyDenied, unavailable }

/// Ask for the camera before touching it.
///
/// The camera plugin does prompt on its own, but only from inside
/// `initialize()`, and a refusal then surfaces as a generic exception. Asking
/// first means a refusal can be explained and recovered from.
Future<CameraAccess> requestCameraAccess() async {
  if (!cameraAvailable) return CameraAccess.unavailable;
  final status = await Permission.camera.request();
  if (status.isGranted || status.isLimited) return CameraAccess.granted;
  if (status.isPermanentlyDenied || status.isRestricted) {
    return CameraAccess.permanentlyDenied;
  }
  return CameraAccess.denied;
}

Future<void> openAppSettingsPage() => openAppSettings();

Future<String?> pickFromGallery() async {
  if (!cameraAvailable) return null;
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    // The OCR model works on the pixels, so a huge image costs time without
    // buying accuracy. This is still far more than enough for thermal print.
    maxWidth: 2400,
  );
  return file?.path;
}

/// Thin wrapper so the scan screen never touches the plugin directly.
class CameraController2 {
  CameraController? _controller;
  String? _lastError;

  bool get ready => _controller?.value.isInitialized ?? false;
  CameraController? get raw => _controller;

  /// The real reason the camera is not working, for the screen to show.
  String? get lastError => _lastError;

  Future<void> initialise() async {
    if (!cameraAvailable) {
      _lastError = 'No camera on this platform.';
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _lastError = 'This device reports no cameras.';
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      _controller = controller;
      _lastError = null;
    } on CameraException catch (e) {
      _lastError = '${e.code}: ${e.description ?? ''}'.trim();
    } catch (e) {
      _lastError = '$e';
    }
  }

  /// Returns the path of the captured photo, or throws with a message worth
  /// showing. Returning null silently is what made a failed capture look like
  /// a failed read.
  Future<String> capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw CaptureException(
        _lastError == null
            ? 'The camera is not ready yet.'
            : 'The camera could not start. $_lastError',
      );
    }
    try {
      final file = await c.takePicture();
      return file.path;
    } on CameraException catch (e) {
      throw CaptureException('The camera failed to take the photo. ${e.code}');
    }
  }

  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}

class CaptureException implements Exception {
  final String message;
  CaptureException(this.message);
  @override
  String toString() => message;
}

class CameraPreviewArea extends StatelessWidget {
  final Widget placeholder;
  final CameraController2? controller;

  const CameraPreviewArea({
    super.key,
    required this.placeholder,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final raw = controller?.raw;
    if (raw == null || !raw.value.isInitialized) return placeholder;
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: raw.value.previewSize?.height ?? 1,
        height: raw.value.previewSize?.width ?? 1,
        child: CameraPreview(raw),
      ),
    );
  }
}
