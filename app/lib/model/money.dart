/// Money handling. Pure Dart.
///
/// Amounts arrive from OCR and from text fields as doubles, because that is
/// what the brief's parser produces. Everything that *divides* money works in
/// integer cents instead, because splitting 10.00 three ways in floating point
/// gives three shares that do not add back up to 10.00.
library;

/// The most any single line may come to.
///
/// Far beyond any bill anybody will ever split, and small enough that a group
/// stuffed with them still cannot overflow integer cents when they are added
/// up and divided.
const double maxAmount = 9999999.99;

/// Cents, with the two ways a double can refuse to be money headed off.
///
/// `double.tryParse` accepts "Infinity" and "NaN", and `(x * 100).round()`
/// throws on both - so pasting either into an amount field took the screen
/// down while it was being laid out. A misread receipt could do the same with
/// a long enough run of digits. Neither is a number anybody meant, so both
/// become something harmless rather than an exception.
int toCents(double amount) {
  if (amount.isNaN) return 0;
  return (amount.clamp(-maxAmount, maxAmount) * 100).round();
}

double fromCents(int cents) => cents / 100.0;

/// Parse a user-typed amount. Comma or dot decimal separator; anything
/// unparseable is zero, matching the prototype.
///
/// The keypad asks for digits, but a paste, a hardware keyboard or a
/// third-party keyboard can put anything in the field, so what comes out here
/// is always a real number within a sane range.
double parseTyped(String raw) {
  final s = raw.trim().replaceAll(',', '.').replaceAll('−', '-');
  final value = double.tryParse(s);
  if (value == null || value.isNaN) return 0;
  return value.clamp(-maxAmount, maxAmount);
}

/// Split [cents] into [n] parts that sum to exactly [cents].
///
/// CORRECTION over the brief and the handoff: LOGIC.md section 5 says shares
/// are computed exact and rounded at display time, and notes that person
/// totals may then disagree by a penny. That is a real defect once the group
/// summary starts netting people off against each other: if the shares of a
/// receipt do not add up to the receipt total, the payer is credited with a
/// different figure from the sum of what everybody owes, and the invariant
/// that all the nets sum to zero quietly breaks.
///
/// Largest-remainder allocation fixes it: divide evenly, then hand the leftover
/// pennies out one each, in order. The order is the party order, so it is
/// stable across recomputation rather than jumping between people.
///
/// Negative totals (discounts) allocate by magnitude and then flip, so that a
/// -0.01 rounding penny lands on the same person it would have for a charge.
List<int> allocate(int cents, int n) {
  if (n <= 0) return const [];
  final negative = cents < 0;
  final magnitude = cents.abs();

  final base = magnitude ~/ n;
  final remainder = magnitude % n;

  return List<int>.generate(n, (i) {
    final v = base + (i < remainder ? 1 : 0);
    return negative ? -v : v;
  });
}

/// Format as the design specifies: symbol before the number, minus sign
/// leading, two decimals. "−€40.00".
String formatMoney(double amount, String symbol) {
  final sign = amount < -0.0000001 ? '−' : '';
  return '$sign$symbol${amount.abs().toStringAsFixed(2)}';
}

String formatCents(int cents, String symbol) =>
    formatMoney(fromCents(cents), symbol);
