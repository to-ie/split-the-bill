import 'package:bill/ocr/ocr_types.dart';
import 'package:bill/parsing/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

OcrWord w(String text, {required double y, required double x, double h = 14}) =>
    OcrWord(
      text: text,
      box: OcrBox(left: x, top: y, right: x + text.length * 7.5, bottom: y + h),
    );

/// Repairing misread prices is only worth having if it does not invent them.
/// These are the things that look like money and are not.
void main() {
  test('a phone number in the header is not a price', () {
    final ocr = OcrResult([
      w('TEL', y: 0, x: 60), w('0851234567', y: 0, x: 95),
      w('COFFEE', y: 24, x: 20), w('3.00', y: 24, x: 300),
      w('CAKE', y: 48, x: 20), w('4.00', y: 48, x: 300),
      w('JUICE', y: 72, x: 20), w('2.50', y: 72, x: 300),
      w('TOTAL', y: 96, x: 20), w('9.50', y: 96, x: 300),
    ]);
    final parsed = parseReceipt(ocr);
    expect(parsed.itemSum, closeTo(9.50, 0.005));
    expect(parsed.lines.first.amount, isNull);
  });

  test('a loyalty number in the price column is rejected on size', () {
    final ocr = OcrResult([
      w('COFFEE', y: 0, x: 20), w('3.00', y: 0, x: 300),
      w('CAKE', y: 24, x: 20), w('4.00', y: 24, x: 300),
      w('JUICE', y: 48, x: 20), w('2.50', y: 48, x: 300),
      w('CARD', y: 72, x: 20), w('99999999999', y: 72, x: 300),
      w('TOTAL', y: 96, x: 20), w('9.50', y: 96, x: 300),
    ]);
    final parsed = parseReceipt(ocr);
    final cardRow = parsed.lines.firstWhere((l) => l.rawText.contains('CARD'));
    expect(cardRow.amount, isNull,
        reason: 'eleven digits is not a price, whatever column it is in');
  });

  test('a date in the left column is not turned into a price', () {
    final ocr = OcrResult([
      w('12/09/2026', y: 0, x: 60),
      w('COFFEE', y: 24, x: 20), w('3.00', y: 24, x: 300),
      w('CAKE', y: 48, x: 20), w('4.00', y: 48, x: 300),
      w('JUICE', y: 72, x: 20), w('2.50', y: 72, x: 300),
      w('TOTAL', y: 96, x: 20), w('9.50', y: 96, x: 300),
    ]);
    expect(parseReceipt(ocr).itemSum, closeTo(9.50, 0.005));
  });

  test('a quantity in the description is not promoted to a price', () {
    final ocr = OcrResult([
      w('BEER', y: 0, x: 20), w('6', y: 0, x: 60), w('X', y: 0, x: 80),
      w('330ML', y: 0, x: 100), w('12.00', y: 0, x: 300),
      w('WINE', y: 24, x: 20), w('18.00', y: 24, x: 300),
      w('WATER', y: 48, x: 20), w('2.00', y: 48, x: 300),
      w('TOTAL', y: 72, x: 20), w('32.00', y: 72, x: 300),
    ]);
    final parsed = parseReceipt(ocr);
    expect(parsed.itemSum, closeTo(32.00, 0.005));
    expect(parsed.items.first.description, contains('330ML'));
  });

  test('a table number is not read as money', () {
    final ocr = OcrResult([
      w('TABLE', y: 0, x: 60), w('12', y: 0, x: 110),
      w('COFFEE', y: 24, x: 20), w('3.00', y: 24, x: 300),
      w('CAKE', y: 48, x: 20), w('4.00', y: 48, x: 300),
      w('JUICE', y: 72, x: 20), w('2.50', y: 72, x: 300),
      w('TOTAL', y: 96, x: 20), w('9.50', y: 96, x: 300),
    ]);
    expect(parseReceipt(ocr).itemSum, closeTo(9.50, 0.005));
  });

  test('with no price column to judge by, nothing is invented', () {
    // Two lines only: too little evidence for a column, so the riskiest
    // repair must stay switched off.
    final ocr = OcrResult([
      w('MEMBER', y: 0, x: 20), w('1234', y: 0, x: 300),
    ]);
    final parsed = parseReceipt(ocr);
    expect(parsed.lines.single.amount, isNull);
  });

  test('a word that happens to contain digits is left alone', () {
    final ocr = OcrResult([
      w('COFFEE', y: 0, x: 20), w('3.00', y: 0, x: 300),
      w('CAKE', y: 24, x: 20), w('4.00', y: 24, x: 300),
      w('JUICE', y: 48, x: 20), w('2.50', y: 48, x: 300),
      w('TILL', y: 72, x: 20), w('A2', y: 72, x: 300),
      w('TOTAL', y: 96, x: 20), w('9.50', y: 96, x: 300),
    ]);
    final till = parseReceipt(ocr).lines.firstWhere(
          (l) => l.rawText.contains('TILL'),
        );
    expect(till.amount, isNull);
  });

  group('repairAmount in isolation', () {
    test('fixes the digits OCR gets wrong', () {
      expect(repairAmount('9.SO', allowLostDecimal: false), 9.50);
      expect(repairAmount('1I.00', allowLostDecimal: false), 11.00);
      expect(repairAmount('B.00', allowLostDecimal: false), 8.00);
      expect(repairAmount('2.OO', allowLostDecimal: false), 2.00);
      expect(repairAmount('l2.5O', allowLostDecimal: false), 12.50);
    });

    test('drops a currency symbol read as a letter', () {
      expect(repairAmount('C2.15', allowLostDecimal: false), 2.15);
      expect(repairAmount('E3.40', allowLostDecimal: false), 3.40);
    });

    test('keeps a genuine tax code', () {
      expect(repairAmount('3.99A', allowLostDecimal: false), 3.99);
      expect(repairAmount('4.5OA', allowLostDecimal: false), 4.50);
    });

    test('only restores a lost decimal when told it is a price', () {
      expect(repairAmount('185', allowLostDecimal: false), isNull);
      expect(repairAmount('185', allowLostDecimal: true), 1.85);
      expect(repairAmount('99999999999', allowLostDecimal: true), isNull);
    });

    test('refuses things that are not money at all', () {
      expect(repairAmount('COFFEE', allowLostDecimal: true), isNull);
      expect(repairAmount('', allowLostDecimal: true), isNull);
      expect(repairAmount('12/09/2026', allowLostDecimal: true), isNull);
      expect(repairAmount('2.99/kg', allowLostDecimal: true), isNull);
    });
  });
}
