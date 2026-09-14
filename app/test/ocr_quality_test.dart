
import 'package:bill/parsing/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ocr_corpus.dart';

/// Scores a parse against what a person would have written down.
({int found, int wanted, List<String> misses}) score(ReceiptFixture f) {
  final parsed = parseReceipt(f.ocr);
  final items = {
    for (final l in parsed.items) l.description.trim(): l.amount,
  };

  final misses = <String>[];
  var found = 0;
  f.expectedItems.forEach((description, amount) {
    final got = items[description];
    if (got != null && (got - amount).abs() < 0.005) {
      found++;
    } else {
      misses.add('$description $amount -> ${got ?? 'missing'}');
    }
  });
  return (found: found, wanted: f.expectedItems.length, misses: misses);
}

void main() {
  for (final fixture in allFixtures()) {
    test('parses every item on the ${fixture.name} receipt', () {
      final s = score(fixture);
      expect(s.found, s.wanted, reason: s.misses.join('\n'));
    });

    test('reads the printed figures on the ${fixture.name} receipt', () {
      final parsed = parseReceipt(fixture.ocr);
      if (fixture.expectedSubtotal != null) {
        expect(parsed.subtotal, closeTo(fixture.expectedSubtotal!, 0.005));
      }
      if (fixture.expectedTotal != null) {
        expect(parsed.total, closeTo(fixture.expectedTotal!, 0.005));
      }
    });

    test('the ${fixture.name} receipt balances after parsing', () {
      final parsed = parseReceipt(fixture.ocr);
      if (!parsed.hasBalanceTarget) return;
      expect(parsed.balances, isTrue,
          reason: 'items came to ${parsed.itemSum}, '
              'receipt says ${parsed.balanceTarget}');
    });
  }
}
