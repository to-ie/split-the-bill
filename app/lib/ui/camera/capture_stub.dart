import 'package:flutter/widgets.dart';

/// Web: there is no camera. The scan screen shows its placeholder and the
/// fake engine supplies a sample receipt.
bool get cameraAvailable => false;

enum CameraAccess { granted, denied, permanentlyDenied, unavailable }

Future<CameraAccess> requestCameraAccess() async => CameraAccess.unavailable;

Future<void> openAppSettingsPage() async {}

Future<String?> pickFromGallery() async => null;

class CaptureException implements Exception {
  final String message;
  CaptureException(this.message);
  @override
  String toString() => message;
}

class CameraController2 {
  Future<void> initialise() async {}
  Future<String> capture() async =>
      throw CaptureException('No camera in the browser.');
  Future<void> dispose() async {}
  bool get ready => false;
  String? get lastError => null;
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
  Widget build(BuildContext context) => placeholder;
}
