import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_engine.dart';
import 'ocr_types.dart';

/// The ONLY file in the project that imports ML Kit.
/// Its job is translation: ML Kit types in, our types out. Nothing else.
///
/// If `google_mlkit_text_recognition` is ever imported anywhere else, the
/// abstraction has leaked. `tool/check_ocr_boundary.sh` fails the build if so.
class MlKitOcrEngine implements OcrEngine {
  final TextRecognizer _recogniser = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  @override
  Future<OcrResult> recognise(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final recognised = await _recogniser.processImage(input);

    final words = <OcrWord>[];
    for (final block in recognised.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final r = element.boundingBox;
          words.add(
            OcrWord(
              text: element.text,
              box: OcrBox(
                left: r.left.toDouble(),
                top: r.top.toDouble(),
                right: r.right.toDouble(),
                bottom: r.bottom.toDouble(),
              ),
              confidence: element.confidence,
            ),
          );
        }
      }
    }
    return OcrResult(words);
  }

  @override
  Future<void> dispose() => _recogniser.close();
}
