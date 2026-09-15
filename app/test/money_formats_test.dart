import 'package:bill/model/money.dart';
import 'package:bill/parsing/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// The app defaults to euros, and half of Europe writes twelve euros fifty as
/// "12,50". Reading that as twelve hundred and fifty, or as nothing at all,
/// would make the app useless everywhere it is most likely to be used.
void main() {
  group('amounts as they are actually printed', () {
    const cases = <String, double?>{
      // Plain
      '12.50': 12.50,
      '12,50': 12.50,
      '0.99': 0.99,
      '0,99': 0.99,
      '1234.56': 1234.56,
      // Thousands separators, both conventions
      '1,234.56': 1234.56,
      '1.234,56': 1234.56,
      '12,345.67': 12345.67,
      '12.345,67': 12345.67,
      // Currency attached
      '€12,50': 12.50,
      '12,50€': 12.50,
      r'$12.50': 12.50,
      '£12.50': 12.50,
      '12,50 EUR': 12.50,
      // Negative and refunds
      '-12,50': -12.50,
      '(12,50)': -12.50,
      '−12,50': -12.50, // a real minus sign, not a hyphen
      // Trailing markers seen on tills
      '12,50*': 12.50,
      '12.50 A': 12.50,
      // Not money
      'Margherita': null,
      '': null,
      '--': null,
    };

    cases.forEach((input, expected) {
      test('"$input"', () {
        final got = parseAmount(input);
        if (expected == null) {
          expect(got, isNull, reason: '"$input" is not an amount');
        } else {
          expect(got, isNotNull, reason: '"$input" should parse');
          expect(got!, closeTo(expected, 0.0001), reason: input);
        }
      });
    });
  });

  group('cents never drift', () {
    test('rounding is half-up and stable', () {
      expect(toCents(12.50), 1250);
      expect(toCents(0.005), 1);
      expect(toCents(-0.005), -1);
      expect(toCents(0.1 + 0.2), 30);
      // 1.005 is not representable in binary: the nearest double is a hair
      // below it, so it rounds down. Documented rather than pretended away;
      // money only ever reaches here with two decimals.
      expect(toCents(1.005), 100);
      expect(toCents(-12.345), -1235);
    });

    test('nothing a keyboard can produce throws', () {
      // Pasting any of these used to take the screen down mid-layout.
      for (final hostile in [
        'Infinity',
        '-Infinity',
        'NaN',
        '1e400',
        '-1e400',
        '999999999999999999999',
        'nonsense',
        '',
      ]) {
        final v = parseTyped(hostile);
        expect(v.isFinite, isTrue, reason: hostile);
        expect(v.abs(), lessThanOrEqualTo(maxAmount), reason: hostile);
        expect(() => toCents(v), returnsNormally, reason: hostile);
      }

      // And straight into toCents, which also takes values read off a photo.
      expect(toCents(double.infinity), toCents(maxAmount));
      expect(toCents(double.negativeInfinity), toCents(-maxAmount));
      expect(toCents(double.nan), 0);
    });

    test('an absurd amount is capped rather than wrapping round', () {
      expect(parseTyped('1e9'), maxAmount);
      expect(toCents(parseTyped('1e9')), 999999999);
      expect(toCents(1e21), toCents(maxAmount),
          reason: 'must not saturate to the integer limit');
    });

    test('a thousand awkward amounts survive the round trip', () {
      for (var i = 0; i < 100000; i += 7) {
        final money = i / 100;
        expect(toCents(money), i, reason: '$money');
      }
    });
  });
}
