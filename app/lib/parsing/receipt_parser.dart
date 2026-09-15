import '../ocr/ocr_types.dart';
import 'receipt.dart';
import 'row_grouper.dart';

/// Money. Tolerates a currency symbol, thousands separators, either decimal
/// separator, a trailing tax-code letter (common on UK and Irish receipts),
/// bracketed or signed negatives.
/// The integer part allows separators but does not require them. Insisting on
/// them meant a four-figure amount printed plainly - "1200.00", as most tills
/// print it - was not recognised as money at all, so the biggest line on a
/// villa or a flight simply vanished, and so did the total. Continental
/// grouping ("1.200,00") was refused for the same reason.
final _amountPattern = RegExp(
  r'^[-−(]?\s*[€£$]?\s*\d+(?:[.,\s]\d{3})*[.,]\d{2}\s*[€£$]?\s*[A-Za-z*]?\)?$',
);

/// Leading quantity: "2", "2x", "2 X".
final _quantityPattern = RegExp(r'^(\d{1,2})\s*[xX×]?$');

/// A bare multiplication sign left behind after a leading quantity is taken.
final _bareTimesPattern = RegExp(r'^[xX×]$');

/// A weighed item: "0.482 kg @ 2.99/kg". The @ makes the row a continuation
/// of the line above rather than a line of its own.
final _weighedPattern = RegExp(r'@');

/// Characters ML Kit reaches for when the thermal print is faint or smudged.
/// Only ever applied to a token already sitting in the price column, where
/// every character is meant to be a digit.
const _confusions = {
  'O': '0',
  'o': '0',
  'D': '0',
  'Q': '0',
  'l': '1',
  'I': '1',
  'i': '1',
  '|': '1',
  '!': '1',
  ']': '1',
  '[': '1',
  'Z': '2',
  'z': '2',
  'S': '5',
  's': '5',
  'G': '6',
  'b': '6',
  'B': '8',
  'g': '9',
  'q': '9',
};

/// A currency symbol misread as the letter it resembles: € as C or E, £ as E,
/// \$ as S. Only stripped from the front of a price-column token.
final _leadingCurrencyLetter = RegExp(r'^[CcEe\u20AC\u00A3$]');

/// A price that lost its decimal point: "185" for 1.85. Only trusted inside
/// an established price column.
final _bareDigits = RegExp(r'^\d{3,7}$');

/// Repairs a token that should be money but was misread.
///
/// Runs in order of how much it assumes: parse it as-is, then fix characters
/// that are only ever digits here, then drop a currency symbol read as a
/// letter, and last of all — and only where a price column has been
/// established, so the token is known to be a price — put back a decimal
/// point that the printer or the camera lost.
///
/// [inPriceColumn] gates the riskiest step. Outside the column a bare run of
/// digits is far more likely to be a loyalty number or a date than a price.
double? repairAmount(String raw, {required bool allowLostDecimal}) {
  final original = raw.trim();
  if (original.isEmpty) return null;
  if (_amountPattern.hasMatch(original)) return parseAmount(original);

  String dropCurrency(String s) => s.replaceFirst(_leadingCurrencyLetter, '');
  String substitute(String s) =>
      s.split('').map((ch) => _confusions[ch] ?? ch).join();

  // In the order of how much each assumes.
  final attempts = <String>[
    // Every character is meant to be a digit: "9.SO", "2.OO", "B.00".
    substitute(dropCurrency(original)),
    // Only a currency symbol was misread: "C2.15".
    dropCurrency(original),
  ];

  // A genuine trailing tax code is a letter on purpose, so try keeping it.
  if (original.length > 1 && RegExp(r'[A-Za-z*]$').hasMatch(original)) {
    final body = dropCurrency(original.substring(0, original.length - 1));
    final suffix = original.substring(original.length - 1);
    attempts.add('${substitute(body)}$suffix');
    attempts.add(substitute(body));
  }

  for (final attempt in attempts) {
    if (_amountPattern.hasMatch(attempt)) {
      final value = parseAmount(attempt);
      if (value != null) return value;
    }
  }

  // Last resort, and only where the token is known to be a price: a decimal
  // point the printer or the camera lost. Outside a price column a bare run
  // of digits is far more likely to be a loyalty number or a date.
  if (allowLostDecimal) {
    for (final attempt in attempts) {
      if (!_bareDigits.hasMatch(attempt)) continue;
      final value = double.tryParse(
        '${attempt.substring(0, attempt.length - 2)}'
        '.${attempt.substring(attempt.length - 2)}',
      );
      if (value != null && value < 100000) return value;
    }
  }

  return null;
}

const _totalWords = ['total', 'amount due', 'balance due', 'to pay'];
const _subtotalWords = ['subtotal', 'sub total', 'sub-total', 'goods'];
const _taxWords = ['vat', 'tax', 'gst'];
const _paymentWords = [
  'cash',
  'card',
  'change',
  'visa',
  'mastercard',
  'debit',
  'credit',
  'contactless',
  'tendered',
];

/// CORRECTION over the brief: the brief put discount words in with tips and
/// service charges. They behave differently (see [LineKind.discount]), so
/// they are now a separate list.
const _adjustmentWords = [
  'service charge',
  'service',
  'tip',
  'gratuity',
  'cover charge',
  'cover',
  'delivery',
];
const _discountWords = [
  'discount',
  'voucher',
  'off',
  'promo',
  'promotion',
  'coupon',
  'saving',
  'savings',
  'loyalty',
  'reduction',
];

final _wordCache = <String, RegExp>{};

/// CORRECTION over the brief: keyword tests used `String.contains`, which
/// matches inside other words. The live example is "off" inside "COFFEE" -
/// every coffee on every receipt was being classified as a discount. Matching
/// on word boundaries fixes that class of bug outright, and it also removes
/// the ordering hazard the brief warned about ("subtotal" no longer contains
/// a matchable "total").
bool _hasWord(String description, List<String> words) {
  for (final w in words) {
    final re = _wordCache[w] ??= RegExp(
      r'(?<![a-z0-9])' + RegExp.escape(w) + r'(?![a-z0-9])',
    );
    if (re.hasMatch(description)) return true;
  }
  return false;
}

double? parseAmount(String raw) {
  var s = raw.trim().replaceAll('−', '-');
  s = s.replaceAll(RegExp(r'[€£$\s]'), '');
  s = s.replaceAll(RegExp(r'[A-Za-z*]+$'), '');

  var negative = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1);
  }
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  }

  // Whichever separator appears last is the decimal separator.
  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  if (lastComma > lastDot) {
    s = s.replaceAll('.', '');
    final i = s.lastIndexOf(',');
    s = '${s.substring(0, i)}.${s.substring(i + 1)}';
  } else {
    s = s.replaceAll(',', '');
  }

  final value = double.tryParse(s);
  if (value == null) return null;
  return negative ? -value : value;
}

LineKind classify(String description, double? amount) {
  final d = description.toLowerCase();

  // Order matters: a row reading "TOTAL INC VAT" is a total, not a tax line.
  if (_hasWord(d, _subtotalWords)) return LineKind.subtotal;
  if (_hasWord(d, _totalWords)) return LineKind.total;
  if (_hasWord(d, _taxWords)) return LineKind.tax;
  if (_hasWord(d, _paymentWords)) return LineKind.payment;
  if (_hasWord(d, _discountWords)) return LineKind.discount;
  if (_hasWord(d, _adjustmentWords)) return LineKind.adjustment;

  if (amount == null) return LineKind.noise;
  if (description.trim().length < 2) return LineKind.noise;

  // A negative amount on an otherwise ordinary row is a deduction, whatever
  // it is called. Receipts are not consistent about naming these.
  if (amount < 0) return LineKind.discount;

  return LineKind.item;
}

/// One row's candidate price: the rightmost money-shaped token.
class _Candidate {
  final int wordIndex;
  final double value;
  final OcrBox box;
  const _Candidate(this.wordIndex, this.value, this.box);
}

_Candidate? _rightmostMoney(OcrRow row) {
  // Scanning from the right is what makes this robust: descriptions often
  // contain numbers ("6 X 330ML"), prices are always last.
  for (var i = row.words.length - 1; i >= 0; i--) {
    final t = row.words[i].text;
    if (!_amountPattern.hasMatch(t)) continue;
    final v = parseAmount(t);
    if (v != null) return _Candidate(i, v, row.words[i].box);
  }
  return null;
}

/// Looks for a misread price in [row], rightmost first.
_Candidate? _repairedCandidate(
  OcrRow row,
  double? columnX,
  double? tolerance, {
  required bool allowLostDecimal,
}) {
  for (var i = row.words.length - 1; i >= 0; i--) {
    final word = row.words[i];

    // A token with no digits at all is a word, not a damaged price.
    if (!RegExp(r'[0-9]').hasMatch(word.text)) continue;

    final inColumn =
        columnX != null &&
        tolerance != null &&
        (word.box.right - columnX).abs() <= tolerance;

    // Once a column is known, only tokens inside it are prices.
    if (columnX != null && !inColumn) continue;

    final value = repairAmount(
      word.text,
      allowLostDecimal: allowLostDecimal && inColumn,
    );
    if (value != null) return _Candidate(i, value, word.box);
  }
  return null;
}

/// Splits a row that has swallowed the line below it.
///
/// A crease or a tight line spacing can leave two printed lines overlapping
/// by more than the grouper's threshold, and they arrive as one row with two
/// prices in it. Left alone that loses a price and glues two descriptions
/// together. Each price in the column seeds a line, and every word in the row
/// goes to whichever price it sits closest to vertically.
List<OcrRow> splitMergedRows(
  List<OcrRow> rows,
  double? columnX,
  double? tolerance,
) {
  if (columnX == null || tolerance == null) return rows;

  final out = <OcrRow>[];
  for (final row in rows) {
    final prices =
        row.words
            .where(
              (w) =>
                  (w.box.right - columnX).abs() <= tolerance &&
                  _amountPattern.hasMatch(w.text),
            )
            .toList()
          ..sort((a, b) => a.box.centreY.compareTo(b.box.centreY));

    if (prices.length < 2) {
      out.add(row);
      continue;
    }

    final buckets = List.generate(prices.length, (_) => <OcrWord>[]);
    for (final word in row.words) {
      var best = 0;
      var bestDistance = double.infinity;
      for (var i = 0; i < prices.length; i++) {
        final d = (word.box.centreY - prices[i].box.centreY).abs();
        if (d < bestDistance) {
          bestDistance = d;
          best = i;
        }
      }
      buckets[best].add(word);
    }

    for (final bucket in buckets) {
      if (bucket.isEmpty) continue;
      bucket.sort((a, b) => a.box.left.compareTo(b.box.left));
      out.add(OcrRow(bucket));
    }
  }

  out.sort((a, b) => a.top.compareTo(b.top));
  return out;
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  if (s.isEmpty) return 0;
  final mid = s.length ~/ 2;
  if (s.length.isOdd) return s[mid];
  return (s[mid - 1] + s[mid]) / 2;
}

/// Brief section 12, the "cheapest high-value improvement, do it first":
/// once several amounts are found, compute the median right-edge x and reject
/// candidates far from that column. This is what kills dates, loyalty card
/// numbers and phone numbers that happen to look like money.
///
/// Skipped when there are fewer than three candidates, because three points
/// is the minimum needed for a median to mean anything.
double? _priceColumnTolerance(List<_Candidate> candidates, OcrResult ocr) {
  if (candidates.length < 3) return null;
  final heights = candidates.map((c) => c.box.height).toList();
  final pageWidth = ocr.pageWidth;
  final byHeight = _median(heights) * 3.0;
  final byPage = pageWidth * 0.12;
  return byHeight > byPage ? byHeight : byPage;
}

ParsedReceipt parseReceipt(
  OcrResult ocr, {
  bool usePriceColumn = true,
  double overlapThreshold = 0.5,
}) {
  final rows = [
    ...groupIntoRows(ocr.words, overlapThreshold: overlapThreshold),
  ];

  // Finding the prices happens in tiers, because locating the price column
  // and reading damaged prices depend on each other. Each tier adds
  // candidates, then the column is recomputed with better evidence.
  final candidates = <int, _Candidate>{};

  double? columnX;
  double? tolerance;

  void recomputeColumn() {
    if (!usePriceColumn) return;
    final found = candidates.values.toList();
    tolerance = _priceColumnTolerance(found, ocr);
    columnX = tolerance == null
        ? null
        : _median(found.map((c) => c.box.right).toList());
  }

  // Tier one: tokens that are unambiguously money.
  for (var r = 0; r < rows.length; r++) {
    final c = _rightmostMoney(rows[r]);
    if (c != null) candidates[r] = c;
  }
  recomputeColumn();

  // With a column in hand, a row holding two prices is two printed lines that
  // the grouper merged. Split them and start the tiers again.
  final split = splitMergedRows(rows, columnX, tolerance);
  if (split.length != rows.length) {
    rows
      ..clear()
      ..addAll(split);
    candidates.clear();
    for (var r = 0; r < rows.length; r++) {
      final c = _rightmostMoney(rows[r]);
      if (c != null) candidates[r] = c;
    }
    recomputeColumn();
  }

  // Tier two: characters that are only ever digits in this position, and
  // currency symbols read as letters. Safe enough to run before the column
  // is certain, and it is often what makes the column findable at all.
  for (var r = 0; r < rows.length; r++) {
    if (candidates.containsKey(r)) continue;
    final c = _repairedCandidate(
      rows[r],
      columnX,
      tolerance,
      allowLostDecimal: false,
    );
    if (c != null) candidates[r] = c;
  }
  recomputeColumn();

  // Tier three: a lost decimal point, inside a column that is now backed by
  // everything found above.
  if (columnX != null) {
    for (var r = 0; r < rows.length; r++) {
      if (candidates.containsKey(r)) continue;
      final c = _repairedCandidate(
        rows[r],
        columnX,
        tolerance,
        allowLostDecimal: true,
      );
      if (c != null) candidates[r] = c;
    }
  }

  // Anything left outside the column is money-shaped but not a price: a
  // date, a loyalty number, a phone number.
  if (columnX != null && tolerance != null) {
    candidates.removeWhere(
      (_, c) => (c.box.right - columnX!).abs() > tolerance!,
    );
  }

  // Pass two: build the lines.
  final lines = <ReceiptLine>[];
  var seq = 0;

  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    final words = [...row.words];
    if (words.isEmpty) continue;

    final candidate = candidates[r];

    double? amount;
    if (candidate != null) {
      amount = candidate.value;
      words.removeAt(candidate.wordIndex);
    }

    // A leading small integer is a quantity, not part of the name.
    //
    // CORRECTION over the brief: after taking the "2" from "2 X PERONI", the
    // brief left the bare "X" in the description. It is now taken too.
    var quantity = 1;
    if (words.length > 1) {
      final m = _quantityPattern.firstMatch(words.first.text);
      if (m != null) {
        quantity = int.parse(m.group(1)!);
        words.removeAt(0);
        if (words.length > 1 && _bareTimesPattern.hasMatch(words.first.text)) {
          words.removeAt(0);
        }
      }
    }

    final description = words.map((w) => w.text).join(' ').trim();

    // Brief section 12: a weighed row ("0.482 kg @ 2.99/kg") is a continuation
    // of the line above, not a line of its own. Fold it into the previous
    // description so its per-kilo price cannot become a second charge.
    // ...but only when it has no price of its own in the price column. A
    // supermarket prints "BANANAS 1.2kg @ 1.50" with what it came to on the
    // right, and folding that into the line above threw the item away and
    // gave its money to whatever was printed before it.
    if (_weighedPattern.hasMatch(description) &&
        amount == null &&
        lines.isNotEmpty) {
      final prev = lines.removeLast();
      lines.add(
        ReceiptLine(
          id: prev.id,
          description: prev.description,
          amount: prev.amount ?? amount,
          quantity: prev.quantity,
          kind: prev.kind == LineKind.noise && (prev.amount ?? amount) != null
              ? classify(prev.description, prev.amount ?? amount)
              : prev.kind,
          rawText: '${prev.rawText}\n${row.text}',
          suspicious: prev.suspicious,
        ),
      );
      continue;
    }

    lines.add(
      ReceiptLine(
        id: 'l${seq++}',
        description: description,
        amount: amount,
        quantity: quantity,
        kind: classify(description, amount),
        rawText: row.text,
      ),
    );
  }

  // Brief section 12: some receipts print the name on one line and the price
  // on the next. Detect a description with no amount followed by an amount
  // with no description, and join them.
  for (var i = 0; i < lines.length - 1; i++) {
    final a = lines[i];
    final b = lines[i + 1];
    final aOrphan = a.amount == null && a.description.trim().length >= 2;
    final bOrphan = b.amount != null && b.description.trim().isEmpty;
    if (aOrphan && bOrphan) {
      lines[i] = ReceiptLine(
        id: a.id,
        description: a.description,
        amount: b.amount,
        quantity: a.quantity,
        kind: classify(a.description, b.amount),
        rawText: '${a.rawText}\n${b.rawText}',
      );
      lines.removeAt(i + 1);
    }
  }

  double? firstAmountOf(LineKind kind) {
    for (final l in lines) {
      if (l.kind == kind && l.amount != null) return l.amount;
    }
    return null;
  }

  final subtotal = firstAmountOf(LineKind.subtotal);
  final tax = firstAmountOf(LineKind.tax);
  final total = firstAmountOf(LineKind.total);

  // CORRECTION, and the resolution of the one real disagreement between the
  // brief and the design handoff. The brief treats tax as a printed summary
  // figure; the handoff treats it as an "Extra (+)" to be split.
  //
  // Both are right, for different receipts:
  //   - UK/EU style, VAT already inside the prices: subtotal == total, and
  //     splitting the VAT line would charge everyone their tax twice.
  //   - US style, sales tax added at the till: subtotal + tax == total, and
  //     the tax must be split or the bill comes up short.
  //
  // The arithmetic tells us which, so we do not have to guess.
  final additive =
      tax != null &&
      subtotal != null &&
      total != null &&
      (subtotal + tax - total).abs() < 0.02 &&
      (subtotal - total).abs() >= 0.02;

  if (additive) {
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].kind == LineKind.tax) {
        lines[i] = lines[i].copyWith(kind: LineKind.adjustment);
        break;
      }
    }
  }

  return ParsedReceipt(
    lines: lines,
    subtotal: subtotal,
    tax: tax,
    total: total,
    taxIsAdditive: additive,
  );
}
