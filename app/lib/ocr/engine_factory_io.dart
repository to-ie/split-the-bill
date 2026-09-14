import 'dart:io';

import 'mlkit_ocr_engine.dart';
import 'mock_ocr_engine.dart';
import 'ocr_engine.dart';

/// Android and iOS get ML Kit. Linux and macOS desktop builds exist only for
/// looking at the UI, so they fall back to the mock.
OcrEngine createOcrEngine() {
  if (Platform.isAndroid || Platform.isIOS) return MlKitOcrEngine();
  return mockEngine();
}

bool get hasRealOcr => Platform.isAndroid || Platform.isIOS;
