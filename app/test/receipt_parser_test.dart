import 'package:bill/ocr/ocr_types.dart';
import 'package:bill/parsing/receipt.dart';
import 'package:bill/parsing/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Helper: place a word at a given row and horizontal position.
OcrWord w(String text,
        {required double y, required double x, double width = 40}) =>
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
      expect(parseAmount('€4.20'), 4.20);
      expect(parseAmount('3.99A'), 3.99);
      expect(parseAmount('1,234.56'), 1234.56);
      expect(parseAmount('4,20'), 4.20);
      expect(parseAmount('-2.00'), -2.00);
      expect(parseAmount('(2.00)'), -2.00);
    });
  });

  group('corrections to the brief', () {
    test('COFFEE is an item, not a discount (substring "off")', () {
      final ocr = OcrResult([
        w('COFFEE', y: 10, x: 10),
        w('3.00', y: 10, x: 300),
      ]);
      expect(parseReceipt(ocr).lines.single.kind, LineKind.item);
    });

    test('CASHEW NUTS is an item, not a payment (substring "cash")', () {
      final ocr = OcrResult([
        w('CASHEW', y: 10, x: 10),
        w('NUTS', y: 10, x: 60),
        w('2.50', y: 10, x: 300),
      ]);
      expect(parseReceipt(ocr).lines.single.kind, LineKind.item);
    });

    test('a real discount is still caught, and goes negative', () {
      final ocr = OcrResult([
        w('10%', y: 10, x: 10),
        w('OFF', y: 10, x: 50),
        w('2.00', y: 10, x: 300),
      ]);
      final line = parseReceipt(ocr).lines.single;
      expect(line.kind, LineKind.discount);
      expect(line.effective, -2.00);
    });

    test('a discount read as positive still subtracts', () {
      const line = ReceiptLine(
        id: 'x',
        description: 'VOUCHER',
        amount: 5.00,
        kind: LineKind.discount,
        rawText: 'VOUCHER 5.00',
      );
      expect(line.effective, -5.00);
    });

    test('TOTAL INC VAT is a total, not a tax line', () {
      final ocr = OcrResult([
        w('TOTAL', y: 10, x: 10),
        w('INC', y: 10, x: 60),
        w('VAT', y: 10, x: 95),
        w('12.00', y: 10, x: 300),
      ]);
      expect(parseReceipt(ocr).lines.single.kind, LineKind.total);
    });

    test('leading quantity takes the bare X with it', () {
      final ocr = OcrResult([
        w('2', y: 10, x: 10),
        w('X', y: 10, x: 30),
        w('PERONI', y: 10, x: 55),
        w('9.00', y: 10, x: 300),
      ]);
      final line = parseReceipt(ocr).lines.single;
      expect(line.quantity, 2);
      expect(line.description, 'PERONI');
    });

    test('a lone amount is not eaten as a quantity', () {
      final ocr = OcrResult([w('7.00', y: 10, x: 300)]);
      final line = parseReceipt(ocr).lines.single;
      expect(line.amount, 7.00);
      expect(line.kind, LineKind.noise); // no description
    });

    test('no subtotal and no total means no balance verdict', () {
      final ocr = OcrResult([
        w('COFFEE', y: 10, x: 10),
        w('3.00', y: 10, x: 300),
      ]);
      final parsed = parseReceipt(ocr);
      expect(parsed.hasBalanceTarget, isFalse);
      expect(parsed.balances, isFalse); // brief behaviour preserved
    });
  });

  group('price column filter', () {
    test('rejects a date in the left column', () {
      // Four priced rows establish the column at x ~ 300-340.
      final ocr = OcrResult([
        w('DATE', y: 0, x: 10),
        w('12.09', y: 0, x: 60), // money-shaped, wrong column
        w('COFFEE', y: 20, x: 10),
        w('3.00', y: 20, x: 300),
        w('CAKE', y: 40, x: 10),
        w('4.00', y: 40, x: 300),
        w('JUICE', y: 60, x: 10),
        w('2.50', y: 60, x: 300),
        w('SCONE', y: 80, x: 10),
        w('2.00', y: 80, x: 300),
      ]);
      final parsed = parseReceipt(ocr);
      final dateRow = parsed.lines.first;
      expect(dateRow.description, contains('12.09'));
      expect(dateRow.amount, isNull);
      expect(parsed.itemSum, closeTo(11.50, 0.001));
    });

    test('is skipped when there is too little evidence', () {
      final ocr = OcrResult([
        w('COFFEE', y: 20, x: 10),
        w('3.00', y: 20, x: 300),
      ]);
      expect(parseReceipt(ocr).lines.single.amount, 3.00);
    });
  });

  group('tax: inclusive vs additive', () {
    List<OcrWord> body() => [
          w('COFFEE', y: 10, x: 10),
          w('6.00', y: 10, x: 300),
          w('CAKE', y: 30, x: 10),
          w('4.00', y: 30, x: 300),
          w('SUBTOTAL', y: 60, x: 10),
          w('10.00', y: 60, x: 300),
        ];

    test('VAT already inside the prices stays a footer figure', () {
      // subtotal 10.00, VAT 1.67, total 10.00 -> inclusive.
      final ocr = OcrResult([
        ...body(),
        w('VAT', y: 80, x: 10),
        w('1.67', y: 80, x: 300),
        w('TOTAL', y: 100, x: 10),
        w('10.00', y: 100, x: 300),
      ]);
      final parsed = parseReceipt(ocr);
      expect(parsed.taxIsAdditive, isFalse);
      expect(parsed.splitRows.length, 2); // just the two items
      expect(parsed.balances, isTrue);
    });

    test('sales tax added at the till becomes a splittable extra', () {
      // subtotal 10.00 + tax 0.80 = total 10.80 -> additive.
      final ocr = OcrResult([
        ...body(),
        w('TAX', y: 80, x: 10),
        w('0.80', y: 80, x: 300),
        w('TOTAL', y: 100, x: 10),
        w('10.80', y: 100, x: 300),
      ]);
      final parsed = parseReceipt(ocr);
      expect(parsed.taxIsAdditive, isTrue);
      expect(parsed.splitRows.length, 3); // two items plus the tax
      expect(parsed.splitSum, closeTo(10.80, 0.001));
      // The balance check still compares items against the subtotal.
      expect(parsed.balances, isTrue);
    });
  });

  group('multi-line and weighed items', () {
    test('a name on one line and a price on the next are joined', () {
      final ocr = OcrResult([
        w('ORGANIC', y: 10, x: 10),
        w('SOURDOUGH', y: 10, x: 70),
        w('4.20', y: 30, x: 300),
        w('MILK', y: 50, x: 10),
        w('1.15', y: 50, x: 300),
        w('BUTTER', y: 70, x: 10),
        w('2.40', y: 70, x: 300),
        w('EGGS', y: 90, x: 10),
        w('3.00', y: 90, x: 300),
      ]);
      final parsed = parseReceipt(ocr);
      expect(parsed.items.first.description, 'ORGANIC SOURDOUGH');
      expect(parsed.items.first.amount, 4.20);
      expect(parsed.itemSum, closeTo(10.75, 0.001));
    });

    test('a weighed row folds into the line above', () {
      final ocr = OcrResult([
        w('BANANAS', y: 10, x: 10),
        w('1.44', y: 10, x: 300),
        w('0.482', y: 25, x: 20),
        w('kg', y: 25, x: 60),
        w('@', y: 25, x: 85),
        w('2.99/kg', y: 25, x: 110),
        w('BREAD', y: 45, x: 10),
        w('2.00', y: 45, x: 300),
        w('JAM', y: 65, x: 10),
        w('3.00', y: 65, x: 300),
      ]);
      final parsed = parseReceipt(ocr);
      expect(parsed.items.length, 3);
      expect(parsed.itemSum, closeTo(6.44, 0.001));
    });
  });
}
