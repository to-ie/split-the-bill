import 'package:bill/ocr/ocr_types.dart';
import 'package:bill/parsing/receipt.dart';
import 'package:bill/parsing/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Receipts that the parser used to get wrong, laid out by geometry the way a
/// photograph gives them to it.
class _Page {
  final List<OcrWord> words = [];
  double y = 0;

  void row(List<(String, double)> cells) {
    for (final (text, x) in cells) {
      words.add(
        OcrWord(
          text: text,
          box: OcrBox(
            left: x,
            top: y,
            right: x + text.length * 7.5,
            bottom: y + 14,
          ),
        ),
      );
    }
    y += 23;
  }

  OcrResult get result => OcrResult(words);
}

Map<String, double?> items(OcrResult r) {
  final parsed = parseReceipt(r);
  return {
    for (final l in parsed.lines)
      if (l.kind != LineKind.noise) l.description: l.amount,
  };
}

void main() {
  group('four figures without a thousands separator', () {
    // Most tills print 1200.00, not 1,200.00. The gate that decides whether a
    // token is money required the separator, so the villa, the flights and
    // the total were all read as text and silently dropped - taking the
    // largest number on the bill with them.
    test('a plain four-figure amount is money', () {
      final p = _Page();
      p.row([('SEASIDE', 70), ('LETTINGS', 120)]);
      p.row([('BEER', 20), ('5.00', 300)]);
      p.row([('VILLA', 20), ('HIRE', 60), ('1200.00', 300)]);
      p.row([('TOTAL', 20), ('1205.00', 300)]);

      final parsed = parseReceipt(p.result);
      final got = items(p.result);
      expect(got['VILLA HIRE'], 1200.00);
      expect(got['BEER'], 5.00);
      expect(parsed.total, 1205.00, reason: 'the total went missing too');
    });

    test('and so is a five-figure one', () {
      final p = _Page();
      p.row([('SHOP', 70)]);
      p.row([('DEPOSIT', 20), ('12500.00', 300)]);
      expect(items(p.result)['DEPOSIT'], 12500.00);
    });

    test('grouped amounts still work, in either convention', () {
      final p = _Page();
      p.row([('SHOP', 70)]);
      p.row([('ENGLISH', 20), ('1,200.00', 300)]);
      p.row([('EUROPEAN', 20), ('1.200,00', 300)]);
      final got = items(p.result);
      expect(got['ENGLISH'], 1200.00);
      expect(got['EUROPEAN'], 1200.00);
    });

    test('a date is still not money', () {
      final p = _Page();
      p.row([('SHOP', 70)]);
      p.row([('12.09.2026', 20), ('09:14', 120)]);
      p.row([('BEER', 20), ('5.00', 300)]);
      final got = items(p.result);
      expect(got.containsKey('12.09.2026 09:14'), isFalse,
          reason: 'a date must not become a line of money');
      expect(got['BEER'], 5.00);
    });
  });

  group('a weighed row that has its own price', () {
    // "0.482 kg @ 2.99/kg" under an item is a continuation of it. But a
    // supermarket prints "BANANAS 1.2kg @ 1.50" with what it came to on the
    // right, and folding that into the line above threw the item away and
    // handed its money to whatever was printed before it - often the shop's
    // own name.
    test('keeps its own line and its own money', () {
      final p = _Page();
      p.row([('BIG', 70), ('MARKET', 100)]);
      p.row([
        ('BANANAS', 20),
        ('1.2kg', 80),
        ('@', 120),
        ('1.50', 145),
        ('1.80', 300),
      ]);
      p.row([('BEER', 20), ('5.00', 300)]);

      final got = items(p.result);
      expect(got['BANANAS 1.2kg @ 1.50'], 1.80);
      expect(got['BIG MARKET'], isNull,
          reason: 'the shop name must not be given the fruit money');
      expect(got['BEER'], 5.00);
    });

    test('a bare per-kilo row with no price still folds upward', () {
      final p = _Page();
      p.row([('BIG', 70), ('MARKET', 100)]);
      p.row([('LOOSE', 20), ('APPLES', 70), ('2.40', 300)]);
      p.row([('0.482', 20), ('kg', 60), ('@', 90), ('4.98/kg', 120)]);
      p.row([('BEER', 20), ('5.00', 300)]);

      final got = items(p.result);
      expect(got.keys.where((k) => k.contains('kg @')), isEmpty,
          reason: 'a per-kilo line is not a charge of its own');
      expect(got['BEER'], 5.00);
    });
  });
}
