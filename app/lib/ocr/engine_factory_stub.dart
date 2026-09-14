import 'mock_ocr_engine.dart';
import 'ocr_engine.dart';

/// Web: no camera, no ML Kit. The scan step replays a synthetic receipt
/// through the real parser.
OcrEngine createOcrEngine() => mockEngine();

bool get hasRealOcr => false;
