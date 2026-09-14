import 'package:bill/ocr/ocr_types.dart';

/// Realistic OCR output, built from geometry rather than from text, so the
/// row grouper and the price-column filter are exercised the way they are on
/// a real photo.
///
/// The misreadings here are the ones ML Kit actually makes on thermal paper:
/// O for 0, l and I for 1, S for 5, B for 8, a lost decimal point, a currency
/// symbol read as a letter, and two lines merged into one when the paper is
/// creased.
class ReceiptFixture {
  final String name;
  final OcrResult ocr;

  /// description -> amount, what a correct parse should produce for items.
  final Map<String, double> expectedItems;
  final double? expectedSubtotal;
  final double? expectedTotal;

  const ReceiptFixture({
    required this.name,
    required this.ocr,
    required this.expectedItems,
    this.expectedSubtotal,
    this.expectedTotal,
  });
}

/// Lays words out on a page. Each row is a list of (text, x) pairs.
class _Page {
  final List<OcrWord> words = [];
  double y = 0;

  /// Rotation, in "pixels of drop per 100 pixels across", to model a photo
  /// taken at a slight angle.
  final double skew;
  final double lineHeight;

  _Page({this.skew = 0, this.lineHeight = 14});

  void row(List<(String, double)> cells, {double? height, double gap = 9}) {
    final h = height ?? lineHeight;
    for (final (text, x) in cells) {
      final drop = x * skew / 100;
      words.add(OcrWord(
        text: text,
        box: OcrBox(
          left: x,
          top: y + drop,
          right: x + text.length * 7.5,
          bottom: y + drop + h,
        ),
      ));
    }
    y += h + gap;
  }

  OcrResult get result => OcrResult(words);
}

/// A clean café bill. The baseline: if this does not parse, nothing will.
ReceiptFixture cleanCafe() {
  final p = _Page();
  p.row([('THE', 70), ('DAILY', 100), ('GRIND', 150)]);
  p.row([('12/09/2026', 70), ('09:14', 150)]);
  p.row([('FLAT', 20), ('WHITE', 60), ('3.40', 300)]);
  p.row([('CAPPUCCINO', 20), ('3.60', 300)]);
  p.row([('ALMOND', 20), ('CROISSANT', 76), ('3.20', 300)]);
  p.row([('SUBTOTAL', 20), ('10.20', 300)]);
  p.row([('TOTAL', 20), ('10.20', 300)]);
  p.row([('CARD', 20), ('10.20', 300)]);
  return ReceiptFixture(
    name: 'clean cafe',
    ocr: p.result,
    expectedItems: {
      'FLAT WHITE': 3.40,
      'CAPPUCCINO': 3.60,
      'ALMOND CROISSANT': 3.20,
    },
    expectedSubtotal: 10.20,
    expectedTotal: 10.20,
  );
}

/// Thermal paper that has been in a pocket. Letters where digits should be.
ReceiptFixture garbledDigits() {
  final p = _Page();
  p.row([('PIZZERIA', 70), ('NAPOLI', 140)]);
  p.row([('MARGHERITA', 20), ('9.SO', 300)]);      // 9.50
  p.row([('DIAVOLA', 20), ('1I.00', 300)]);        // 11.00
  p.row([('TIRAMISU', 20), ('6.5O', 300)]);        // 6.50
  p.row([('BIRRA', 20), ('MORETTI', 70), ('B.00', 300)]); // 8.00
  p.row([('ACQUA', 20), ('2.OO', 300)]);           // 2.00
  p.row([('SUBTOTAL', 20), ('37.00', 300)]);
  p.row([('TOTAL', 20), ('37.00', 300)]);
  return ReceiptFixture(
    name: 'garbled digits',
    ocr: p.result,
    expectedItems: {
      'MARGHERITA': 9.50,
      'DIAVOLA': 11.00,
      'TIRAMISU': 6.50,
      'BIRRA MORETTI': 8.00,
      'ACQUA': 2.00,
    },
    expectedSubtotal: 37.00,
    expectedTotal: 37.00,
  );
}

/// A till that prints the currency symbol, which OCR reads as a letter, and
/// one price whose decimal point has vanished.
ReceiptFixture lostSeparators() {
  final p = _Page();
  p.row([('CORNER', 70), ('SHOP', 130)]);
  p.row([('MILK', 20), ('2L', 60), ('C2.15', 300)]);   // €2.15
  p.row([('BREAD', 20), ('185', 300)]);                // 1.85
  p.row([('EGGS', 20), ('X6', 60), ('E3.40', 300)]);   // £3.40
  p.row([('BUTTER', 20), ('2.60', 300)]);
  p.row([('TOTAL', 20), ('10.00', 300)]);
  return ReceiptFixture(
    name: 'lost separators',
    ocr: p.result,
    expectedItems: {
      'MILK 2L': 2.15,
      'BREAD': 1.85,
      'EGGS X6': 3.40,
      'BUTTER': 2.60,
    },
    expectedTotal: 10.00,
  );
}

/// A creased receipt: two item lines close enough together that ML Kit's
/// boxes overlap and the grouper merges them.
ReceiptFixture creasedRows() {
  final p = _Page(lineHeight: 16);
  p.row([('TRATTORIA', 70), ('ROMA', 150)]);
  p.row([('BRUSCHETTA', 20), ('6.00', 300)], gap: 2);
  p.row([('CARBONARA', 20), ('12.50', 300)], gap: 9);
  p.row([('INSALATA', 20), ('7.00', 300)]);
  p.row([('VINO', 20), ('ROSSO', 60), ('18.00', 300)]);
  p.row([('SUBTOTAL', 20), ('43.50', 300)]);
  p.row([('TOTAL', 20), ('43.50', 300)]);
  return ReceiptFixture(
    name: 'creased rows',
    ocr: p.result,
    expectedItems: {
      'BRUSCHETTA': 6.00,
      'CARBONARA': 12.50,
      'INSALATA': 7.00,
      'VINO ROSSO': 18.00,
    },
    expectedSubtotal: 43.50,
    expectedTotal: 43.50,
  );
}

/// A crease squashes two printed lines into one band, so they arrive from
/// the grouper as a single row holding two prices.
ReceiptFixture mergedByCrease() {
  final p = _Page();
  p.words.addAll([
    _at('BRUSCHETTA', x: 20, y: 0), _at('6.00', x: 300, y: 2),
    _at('CARBONARA', x: 20, y: 9), _at('12.50', x: 300, y: 11),
    _at('INSALATA', x: 20, y: 40), _at('7.00', x: 300, y: 40),
    _at('VINO', x: 20, y: 64), _at('ROSSO', x: 60, y: 64),
    _at('18.00', x: 300, y: 64),
    _at('SUBTOTAL', x: 20, y: 88), _at('43.50', x: 300, y: 88),
    _at('TOTAL', x: 20, y: 112), _at('43.50', x: 300, y: 112),
  ]);
  return ReceiptFixture(
    name: 'merged by a crease',
    ocr: p.result,
    expectedItems: {
      'BRUSCHETTA': 6.00,
      'CARBONARA': 12.50,
      'INSALATA': 7.00,
      'VINO ROSSO': 18.00,
    },
    expectedSubtotal: 43.50,
    expectedTotal: 43.50,
  );
}

OcrWord _at(String text, {required double x, required double y}) => OcrWord(
      text: text,
      box: OcrBox(
          left: x, top: y, right: x + text.length * 7.5, bottom: y + 14),
    );

/// Photographed at an angle, so every line drops as it crosses the page.
ReceiptFixture skewed() {
  final p = _Page(skew: 4.5);
  p.row([('BISTRO', 70), ('VERT', 140)]);
  p.row([('SOUPE', 20), ('DU', 62), ('JOUR', 88), ('6.50', 300)]);
  p.row([('STEAK', 20), ('FRITES', 62), ('18.00', 300)]);
  p.row([('TARTE', 20), ('TATIN', 62), ('7.50', 300)]);
  p.row([('CAFE', 20), ('2.50', 300)]);
  p.row([('SUBTOTAL', 20), ('34.50', 300)]);
  p.row([('TOTAL', 20), ('34.50', 300)]);
  return ReceiptFixture(
    name: 'skewed',
    ocr: p.result,
    expectedItems: {
      'SOUPE DU JOUR': 6.50,
      'STEAK FRITES': 18.00,
      'TARTE TATIN': 7.50,
      'CAFE': 2.50,
    },
    expectedSubtotal: 34.50,
    expectedTotal: 34.50,
  );
}

/// A supermarket slip: tax-code suffixes, a weighed item, a multibuy
/// discount, and a loyalty card number that looks like money.
ReceiptFixture supermarket() {
  final p = _Page();
  p.row([('FRESH', 70), ('MARKET', 130)]);
  p.row([('CARD', 60), ('4.929', 120)]); // loyalty number, not a price
  p.row([('BANANAS', 20), ('1.44', 300)]);
  p.row([('0.482', 30), ('kg', 70), ('@', 95), ('2.99/kg', 120)]);
  p.row([('CHEDDAR', 20), ('4.50A', 300)]);
  p.row([('COFFEE', 20), ('BEANS', 76), ('7.25', 300)]);
  p.row([('3', 20), ('FOR', 40), ('2', 70), ('OFF', 92), ('2.50', 300)]);
  p.row([('SUBTOTAL', 20), ('13.19', 300)]);
  p.row([('VAT', 20), ('0.00', 300)]);
  p.row([('TOTAL', 20), ('13.19', 300)]);
  return ReceiptFixture(
    name: 'supermarket',
    ocr: p.result,
    expectedItems: {
      'BANANAS': 1.44,
      'CHEDDAR': 4.50,
      'COFFEE BEANS': 7.25,
    },
    expectedSubtotal: 13.19,
    expectedTotal: 13.19,
  );
}

List<ReceiptFixture> allFixtures() => [
      cleanCafe(),
      garbledDigits(),
      lostSeparators(),
      creasedRows(),
      mergedByCrease(),
      skewed(),
      supermarket(),
    ];
