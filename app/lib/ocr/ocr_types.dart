/// Pure Dart. No Flutter, no ML Kit, no dart:io, no dart:ui.
/// Everything downstream of the OCR boundary speaks only these types.
library;

class OcrBox {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const OcrBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;
  double get centreX => (left + right) / 2;
  double get centreY => (top + bottom) / 2;

  /// Vertical overlap with another box, expressed as a fraction of the
  /// shorter of the two. 1.0 means one fully contains the other vertically,
  /// 0.0 means no overlap. This is the core test for "same row".
  ///
  /// Using a ratio rather than an absolute pixel tolerance means it works
  /// regardless of image resolution or font size.
  double verticalOverlapRatio(OcrBox other) {
    final overlapTop = top > other.top ? top : other.top;
    final overlapBottom = bottom < other.bottom ? bottom : other.bottom;
    final overlap = overlapBottom - overlapTop;
    if (overlap <= 0) return 0;

    final shorter = height < other.height ? height : other.height;
    if (shorter <= 0) return 0;
    return overlap / shorter;
  }
}

class OcrWord {
  final String text;
  final OcrBox box;

  /// Often null on Android. Do not build logic that depends on it.
  final double? confidence;

  const OcrWord({required this.text, required this.box, this.confidence});
}

class OcrResult {
  final List<OcrWord> words;
  const OcrResult(this.words);

  /// Rightmost edge of any word. Stands in for the page width, which the
  /// OCR boundary deliberately does not carry. Used to scale tolerances
  /// so they hold at any image resolution.
  double get pageWidth {
    if (words.isEmpty) return 0;
    return words.map((w) => w.box.right).reduce((a, b) => a > b ? a : b);
  }
}
