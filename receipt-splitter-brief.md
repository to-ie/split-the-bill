# Receipt Splitter: Project Brief and Starting Code

Hand this to a new session. It covers what we're building, why, the decisions already
made, and the two hardest pieces of code already designed.

---

## 1. What we're building

A mobile app that photographs a receipt, extracts the line items via OCR, and splits
the bill between people.

**Non-negotiable constraint: privacy.** Receipt data never leaves the device. No
server, no database, no accounts, no cloud OCR. This drives every decision below.

---

## 2. How we got here

Started as a Django web app. Abandoned, because if the image never leaves the device
there is nothing for a server to do. Django would just be a static file server.

Also considered browser OCR (`tesseract.js` as a PWA). Viable but rejected on
accuracy: Tesseract is poor on crumpled thermal paper, and the ~12MB WASM download is
slow on older phones.

Rejected Kivy and BeeWare despite the user's Python background. Painful camera and ML
Kit access, bad packaging, small community.

---

## 3. Stack

- **Flutter / Dart**, single codebase
- **Android first, iOS later.** iOS cannot be compiled from Linux
- **OCR:** `google_mlkit_text_recognition` (ML Kit Text Recognition v2), on-device
- **Storage:** local only, `sqflite` or JSON on disk
- **No backend of any kind**

Packages: `camera`, `google_mlkit_text_recognition`, `sqflite`, `path_provider`

---

## 4. Environment

Ubuntu, **VS Code as the editor** with the `Dart-Code.flutter` extension. Android
Studio is not used for editing, only as an optional SDK bundle. Android SDK via
command line tools. Flutter cloned from git, not snap. JDK 17.

**Testing on a physical Android phone, not the emulator.** The emulator's fake camera
scene makes it useless for receipt OCR.

---

## 5. OCR: how it works, and the privacy position

ML Kit runs a TensorFlow Lite model locally. A CNN locates text regions, a sequence
decoder reads characters. Output is a hierarchy of blocks, lines, elements (words) and
symbols, each with a bounding box.

Google's terms: input images and OCR output are processed fully on-device and are not
sent to Google servers. However the SDK does contact Google for model updates and
sends performance telemetry about the API. ML Kit is a closed binary and its terms
forbid reverse engineering.

Two mitigations agreed:

1. Bundle the model in the APK, then test with network permission denied. If OCR still
   works, that is empirical proof rather than a policy promise.
2. Put OCR behind an app-defined interface. Swapping in Tesseract or PaddleOCR later
   must be a one-class change. This is implemented in section 7.

---

## 6. Architecture

```
lib/
  ocr/
    ocr_types.dart          pure Dart value types, no platform imports
    ocr_engine.dart         abstract interface
    mlkit_ocr_engine.dart   the ONLY file that imports ML Kit
  parsing/
    row_grouper.dart        words + geometry -> rows
    receipt.dart            domain model
    receipt_parser.dart     rows -> line items
test/
  row_grouper_test.dart
  receipt_parser_test.dart
```

**The rule that makes this work:** `ocr_types.dart` uses no Flutter and no platform
imports, only core Dart. Everything downstream of the OCR boundary speaks these types
and nothing else. Two consequences:

- Swapping OCR engines touches one file.
- The parser is testable with plain `dart test`, no device, no emulator, no camera.
  You can iterate on parsing logic in a sub-second feedback loop.

If `google_mlkit_text_recognition` is ever imported outside `mlkit_ocr_engine.dart`,
the abstraction has leaked. Worth a lint rule or a grep in CI.

---

## 7. The OCR boundary

### `lib/ocr/ocr_types.dart`

```dart
/// Pure Dart. No Flutter, no ML Kit, no dart:io, no dart:ui.
/// Everything downstream of the OCR boundary speaks only these types.

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
}
```

### `lib/ocr/ocr_engine.dart`

```dart
import 'ocr_types.dart';

/// The seam. Every OCR implementation sits behind this.
abstract class OcrEngine {
  /// Recognise text in the image at [imagePath].
  /// Path rather than File keeps this free of dart:io.
  Future<OcrResult> recognise(String imagePath);

  Future<void> dispose();
}
```

### `lib/ocr/mlkit_ocr_engine.dart`

```dart
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_engine.dart';
import 'ocr_types.dart';

/// The ONLY file in the project that imports ML Kit.
/// Its job is translation: ML Kit types in, our types out. Nothing else.
class MlKitOcrEngine implements OcrEngine {
  final TextRecognizer _recogniser =
      TextRecognizer(script: TextRecognitionScript.latin);

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
                left: r.left,
                top: r.top,
                right: r.right,
                bottom: r.bottom,
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
```

Note we flatten to **elements (words)**, discarding ML Kit's own line grouping. That
is deliberate. ML Kit's line grouping is tuned for prose and frequently merges a
receipt's description column with its price column, or splits one visual row into two.
We do our own grouping from raw geometry, which we control and can tune.

### Fake engine for tests

```dart
class FakeOcrEngine implements OcrEngine {
  final OcrResult result;
  FakeOcrEngine(this.result);

  @override
  Future<OcrResult> recognise(String imagePath) async => result;

  @override
  Future<void> dispose() async {}
}
```

---

## 8. Row grouping

Receipts are two-column: description on the left, price on the right. The whole
parsing strategy rests on reconstructing rows from geometry rather than running regex
over flattened text.

### `lib/parsing/row_grouper.dart`

```dart
import '../ocr/ocr_types.dart';

class OcrRow {
  /// Words ordered left to right.
  final List<OcrWord> words;
  const OcrRow(this.words);

  String get text => words.map((w) => w.text).join(' ');

  double get top =>
      words.map((w) => w.box.top).reduce((a, b) => a < b ? a : b);
  double get bottom =>
      words.map((w) => w.box.bottom).reduce((a, b) => a > b ? a : b);
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
```

**Tuning note.** `overlapThreshold` is the single most important dial in the whole
app. Too low and adjacent rows merge. Too high and a row splits where the price is
printed in a smaller font than the description, which is common. Start at 0.5 and
adjust against real receipts.

---

## 9. Parsing rows into line items

### `lib/parsing/receipt.dart`

```dart
enum LineKind {
  /// A purchased thing. Gets split between people.
  item,

  /// Service charge, tip, discount. Apportioned across people
  /// rather than assigned to one.
  adjustment,

  subtotal,
  tax,
  total,

  /// Cash, card, change given. Informational only.
  payment,

  /// Shop name, address, date, thanks-for-shopping.
  noise,
}

class ReceiptLine {
  final String description;
  final double? amount;
  final int quantity;
  final LineKind kind;

  /// Kept so the correction UI can show the user what was actually read.
  final String rawText;

  const ReceiptLine({
    required this.description,
    required this.amount,
    required this.quantity,
    required this.kind,
    required this.rawText,
  });
}

class ParsedReceipt {
  final List<ReceiptLine> lines;
  final double? subtotal;
  final double? tax;
  final double? total;

  const ParsedReceipt({
    required this.lines,
    this.subtotal,
    this.tax,
    this.total,
  });

  Iterable<ReceiptLine> get items =>
      lines.where((l) => l.kind == LineKind.item);

  double get itemSum =>
      items.fold(0.0, (sum, l) => sum + (l.amount ?? 0));

  /// Does the arithmetic hold? If false, OCR misread something and the
  /// correction UI should say so loudly rather than quietly being wrong.
  /// Tolerance absorbs rounding, not errors.
  bool get balances {
    final target = subtotal ?? total;
    if (target == null) return false;
    return (itemSum - target).abs() < 0.02;
  }
}
```

### `lib/parsing/receipt_parser.dart`

```dart
import '../ocr/ocr_types.dart';
import 'receipt.dart';
import 'row_grouper.dart';

/// Money. Tolerates a currency symbol, thousands separators, either decimal
/// separator, a trailing tax-code letter (common on UK and Irish receipts),
/// bracketed or signed negatives.
final _amountPattern = RegExp(
  r'^[-\u2212(]?\s*[\u20AC\u00A3$]?\s*\d{1,3}(?:[,\s]\d{3})*[.,]\d{2}\s*[A-Za-z*]?\)?$',
);

/// Leading quantity: "2", "2x", "2 X".
final _quantityPattern = RegExp(r'^(\d{1,2})\s*[xX\u00D7]?$');

const _totalWords = ['total', 'amount due', 'balance due', 'to pay'];
const _subtotalWords = ['subtotal', 'sub total', 'sub-total', 'goods'];
const _taxWords = ['vat', 'tax', 'gst'];
const _paymentWords = [
  'cash', 'card', 'change', 'visa', 'mastercard',
  'debit', 'credit', 'contactless', 'tendered',
];
const _adjustmentWords = [
  'service charge', 'service', 'tip', 'gratuity',
  'discount', 'voucher', 'off',
];

double? parseAmount(String raw) {
  var s = raw.trim().replaceAll('\u2212', '-');
  s = s.replaceAll(RegExp(r'[\u20AC\u00A3$\s]'), '');
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

LineKind _classify(String description, double? amount) {
  final d = description.toLowerCase();
  bool has(List<String> words) => words.any(d.contains);

  // Order matters. "subtotal" contains "total", so test it first.
  if (has(_subtotalWords)) return LineKind.subtotal;
  if (has(_taxWords)) return LineKind.tax;
  if (has(_totalWords)) return LineKind.total;
  if (has(_paymentWords)) return LineKind.payment;
  if (has(_adjustmentWords)) return LineKind.adjustment;

  if (amount == null) return LineKind.noise;
  if (description.trim().length < 2) return LineKind.noise;
  return LineKind.item;
}

ParsedReceipt parseReceipt(OcrResult ocr) {
  final rows = groupIntoRows(ocr.words);
  final lines = <ReceiptLine>[];

  for (final row in rows) {
    final words = [...row.words];
    if (words.isEmpty) continue;

    // The rightmost token that looks like money is the price.
    // Scanning from the right is what makes this robust: descriptions
    // often contain numbers ("6 X 330ML"), prices are always last.
    double? amount;
    for (var i = words.length - 1; i >= 0; i--) {
      if (_amountPattern.hasMatch(words[i].text)) {
        amount = parseAmount(words[i].text);
        if (amount != null) {
          words.removeAt(i);
          break;
        }
      }
    }

    // A leading small integer is a quantity, not part of the name.
    var quantity = 1;
    if (words.isNotEmpty) {
      final m = _quantityPattern.firstMatch(words.first.text);
      if (m != null) {
        quantity = int.parse(m.group(1)!);
        words.removeAt(0);
      }
    }

    final description = words.map((w) => w.text).join(' ').trim();
    lines.add(
      ReceiptLine(
        description: description,
        amount: amount,
        quantity: quantity,
        kind: _classify(description, amount),
        rawText: row.text,
      ),
    );
  }

  double? firstAmountOf(LineKind kind) {
    for (final l in lines) {
      if (l.kind == kind && l.amount != null) return l.amount;
    }
    return null;
  }

  return ParsedReceipt(
    lines: lines,
    subtotal: firstAmountOf(LineKind.subtotal),
    tax: firstAmountOf(LineKind.tax),
    total: firstAmountOf(LineKind.total),
  );
}
```

---

## 10. Tests

Because nothing above touches Flutter or ML Kit, these run with `dart test` in
milliseconds. Build fixtures by hand: coordinates are just numbers.

### `test/receipt_parser_test.dart`

```dart
import 'package:test/test.dart';
import 'package:receipt_splitter/ocr/ocr_types.dart';
import 'package:receipt_splitter/parsing/receipt.dart';
import 'package:receipt_splitter/parsing/receipt_parser.dart';

/// Helper: place a word at a given row and horizontal position.
OcrWord w(String text, {required double y, required double x, double width = 40}) =>
    OcrWord(
      text: text,
      box: OcrBox(left: x, top: y, right: x + width, bottom: y + 12),
    );

void main() {
  test('pairs description with rightmost price', () {
    final ocr = OcrResult([
      w('FLAT', y: 100, x: 10),
      w('WHITE', y: 100, x: 55),
      w('3.40', y: 101, x: 300),
    ]);

    final parsed = parseReceipt(ocr);
    expect(parsed.lines.single.description, 'FLAT WHITE');
    expect(parsed.lines.single.amount, 3.40);
    expect(parsed.lines.single.kind, LineKind.item);
  });

  test('numbers inside a description do not become the price', () {
    final ocr = OcrResult([
      w('BEER', y: 50, x: 10),
      w('6', y: 50, x: 55),
      w('X', y: 50, x: 75),
      w('330ML', y: 50, x: 95),
      w('12.00', y: 50, x: 300),
    ]);

    expect(parseReceipt(ocr).lines.single.amount, 12.00);
  });

  test('subtotal is not misread as total', () {
    final ocr = OcrResult([
      w('SUBTOTAL', y: 200, x: 10),
      w('15.40', y: 200, x: 300),
    ]);

    expect(parseReceipt(ocr).lines.single.kind, LineKind.subtotal);
  });

  test('balances flags a misread digit', () {
    final ocr = OcrResult([
      w('COFFEE', y: 10, x: 10),
      w('3.00', y: 10, x: 300),
      w('CAKE', y: 30, x: 10),
      w('4.00', y: 30, x: 300),
      w('SUBTOTAL', y: 60, x: 10),
      w('9.00', y: 60, x: 300), // wrong on purpose
    ]);

    expect(parseReceipt(ocr).balances, isFalse);
  });

  group('parseAmount', () {
    test('handles currency symbols and tax codes', () {
      expect(parseAmount('\u20AC4.20'), 4.20);
      expect(parseAmount('3.99A'), 3.99);
      expect(parseAmount('1,234.56'), 1234.56);
      expect(parseAmount('4,20'), 4.20);
      expect(parseAmount('-2.00'), -2.00);
      expect(parseAmount('(2.00)'), -2.00);
    });
  });
}
```

Add `test: ^1.24.0` under `dev_dependencies` in `pubspec.yaml`.

---

## 11. The correction UI is the main screen, not a fallback

Parsing will be wrong often enough that editing must be frictionless. Design for it
from the start:

- Show `rawText` alongside the parsed fields so the user can see what was read.
- Make `kind` a dropdown. Misclassification is the most common failure and the
  cheapest to fix by hand.
- When `balances` is false, say so at the top of the screen. A quietly wrong split is
  much worse than an obviously wrong one.
- Let rows be merged and split. Row grouping will occasionally get it wrong and no
  amount of threshold tuning fixes every receipt.
- Consider keeping the photo and drawing the bounding boxes over it. Tapping a box to
  fix its text is far nicer than retyping a line, and you already have the geometry.

---

## 12. Known weaknesses and the next refinements

- **Price column detection.** Once several amounts are found, compute the median
  right-edge x. Reject candidate amounts far from that column. This kills most false
  positives, for example dates and loyalty card numbers. Cheapest high-value
  improvement, do it first.
- **Digit confusion.** OCR mixes O/0, S/5, l/1, B/8. A normalisation pass applied only
  to tokens in the price column is usually safe. Applying it to descriptions is not.
- **Multi-line items.** Some receipts print the name on one line and the price on the
  next. Detect via a row with a description and no amount followed by a row with an
  amount and no description.
- **Skew.** Heavy rotation breaks row grouping. Either deskew the image first, or use
  ML Kit's `cornerPoints` to estimate the angle and rotate the boxes before grouping.
- **Weighted items.** "0.482 kg @ 2.99/kg" produces spurious amounts. Detect the `@`
  and treat the row as a continuation of the line above.

---

## 13. iOS portability rules, apply from day one

- Check platform badges on pub.dev before adding any package. An Android-only
  dependency is the usual thing that makes a port expensive.
- No Kotlin and no MethodChannel unless genuinely forced. Everything in Dart stays free.
- `path_provider` for all file paths, never hardcoded.
- The `ios/` folder already exists from `flutter create`. Leave it intact.
- Only expected divergence is permissions: `AndroidManifest.xml` now,
  `NSCameraUsageDescription` in `Info.plist` later.
- All the parsing code above is pure Dart, so it ports at zero cost. That is most of
  the app's actual logic and the main reason for the architecture.
- Risk: if iOS stays uncompiled for a year, drift makes the port painful. Consider
  periodic macOS CI builds via Codemagic or GitHub Actions.

---

## 14. Distribution

Sideloaded APK for personal use. No store, no fee, no review. Best fit for a privacy
tool.

If Play Store later: personal developer accounts created after 13 November 2023 need a
closed test with at least 12 testers opted in continuously for 14 days before
production access is granted. Apple Developer is 99 euro a year against Google's
one-off 25 dollars.

---

## 15. Working preferences

British English. Terse, plain language, no long dashes. Commands listed in the order
they should be run, with short explanations. The user knows AWS, Intune, Python and
sysadmin work well. New to Android and Flutter, so explain mobile-specific concepts but
skip general engineering basics.
