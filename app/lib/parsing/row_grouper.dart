import '../ocr/ocr_types.dart';

class OcrRow {
  /// Words ordered left to right.
  final List<OcrWord> words;
  const OcrRow(this.words);

  String get text => words.map((w) => w.text).join(' ');

  double get top => words.map((w) => w.box.top).reduce((a, b) => a < b ? a : b);
  double get bottom =>
      words.map((w) => w.box.bottom).reduce((a, b) => a > b ? a : b);

  /// Median word height in this row. Used to scale tolerances.
  double get medianHeight {
    final hs = words.map((w) => w.box.height).toList()..sort();
    return hs[hs.length ~/ 2];
  }
}

/// Group loose words into visual rows using vertical overlap.
///
/// A word joins a row if it vertically overlaps ANY word already in that row
/// by at least [overlapThreshold]. Checking against any word, rather than
/// against a running union of the row's bounds, matters for two reasons:
///
///   - Union-based bands drift downward on a skewed photo and eventually
///     swallow the next row.
///   - Seed-based bands fail when the first word in a row is unusually short.
///
/// Rows are short, so the extra comparisons cost nothing in practice.
List<OcrRow> groupIntoRows(
  List<OcrWord> words, {
  double overlapThreshold = 0.5,
}) {
  if (words.isEmpty) return const [];

  final sorted = [...words]
    ..sort((a, b) => a.box.centreY.compareTo(b.box.centreY));

  final rows = <List<OcrWord>>[];
  var current = <OcrWord>[sorted.first];

  for (final word in sorted.skip(1)) {
    final belongs = current.any(
      (existing) =>
          word.box.verticalOverlapRatio(existing.box) >= overlapThreshold,
    );

    if (belongs) {
      current.add(word);
    } else {
      rows.add(current);
      current = [word];
    }
  }
  rows.add(current);

  return rows.map((row) {
    row.sort((a, b) => a.box.left.compareTo(b.box.left));
    return OcrRow(row);
  }).toList();
}
