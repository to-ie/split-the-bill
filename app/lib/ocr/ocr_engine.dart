import 'ocr_types.dart';

/// The seam. Every OCR implementation sits behind this.
abstract class OcrEngine {
  /// Recognise text in the image at [imagePath].
  /// Path rather than File keeps this free of dart:io.
  Future<OcrResult> recognise(String imagePath);

  Future<void> dispose();
}

/// Returns a fixed result. Used by tests and by the desktop/web build,
/// where there is no camera and no ML Kit.
class FakeOcrEngine implements OcrEngine {
  final OcrResult result;
  final Duration delay;

  FakeOcrEngine(this.result, {this.delay = Duration.zero});

  @override
  Future<OcrResult> recognise(String imagePath) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return result;
  }

  @override
  Future<void> dispose() async {}
}
