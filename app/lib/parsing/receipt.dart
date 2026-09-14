/// Domain model for a parsed receipt. Pure Dart.
library;

/// What a row on the receipt is.
///
/// CORRECTION over the brief: the brief's enum had no `discount`, while the
/// design handoff's correction UI offers four choices (Item, Extra +,
/// Discount -, Ignore). A discount is not an adjustment: its effective amount
/// is always negative regardless of how OCR read the sign, so it needs its own
/// kind rather than a negative `adjustment`.
///
/// The footer kinds (subtotal, tax, total, payment) are kept because the
/// balance check and the printed footer need them. The UI collapses all of
/// them, plus `noise`, onto the single "Ignore" chip.
enum LineKind {
  /// A purchased thing. Gets split between people.
  item,

  /// Service charge, tip, cover charge. Split between the people who agree
  /// to share it, not apportioned automatically.
  adjustment,

  /// Discount, voucher, loyalty saving. Effective amount always negative.
  discount,

  subtotal,
  tax,
  total,

  /// Cash, card, change given. Informational only.
  payment,

  /// Shop name, address, date, thanks-for-shopping.
  noise;

  /// The three kinds that take part in a split. Everything else is either
  /// a printed summary figure or noise.
  bool get isSplittable =>
      this == LineKind.item ||
      this == LineKind.adjustment ||
      this == LineKind.discount;

  /// The four choices offered by the correction UI.
  static const uiChoices = [
    LineKind.item,
    LineKind.adjustment,
    LineKind.discount,
    LineKind.noise,
  ];

  String get chipLabel => switch (this) {
    LineKind.item => 'Item',
    LineKind.adjustment => 'Extra (+)',
    LineKind.discount => 'Discount (-)',
    _ => 'Ignore',
  };

  /// Which chip is shown as selected for this kind. Footer kinds map to
  /// Ignore, so round-tripping a subtotal row through the editor without
  /// touching it must not silently turn it into an item.
  LineKind get uiChoice => isSplittable ? this : LineKind.noise;
}

class ReceiptLine {
  final String id;
  final String description;
  final double? amount;
  final int quantity;
  final LineKind kind;

  /// Kept so the correction UI can show the user what was actually read.
  final String rawText;

  /// OCR output that looks wrong. Highlighted amber. Cleared by any edit.
  final bool suspicious;

  /// Added by hand rather than read from the receipt.
  final bool custom;

  const ReceiptLine({
    required this.id,
    required this.description,
    required this.amount,
    this.quantity = 1,
    required this.kind,
    required this.rawText,
    this.suspicious = false,
    this.custom = false,
  });

  /// The amount that actually counts towards a split.
  ///
  /// A discount is negative whatever sign OCR read: receipts print discounts
  /// as "2.00", "-2.00" and "(2.00)" interchangeably and the user should not
  /// have to care which.
  double get effective {
    final a = amount ?? 0;
    return kind == LineKind.discount ? -a.abs() : a;
  }

  ReceiptLine copyWith({
    String? description,
    double? amount,
    bool clearAmount = false,
    int? quantity,
    LineKind? kind,
    bool? suspicious,
  }) {
    return ReceiptLine(
      id: id,
      description: description ?? this.description,
      amount: clearAmount ? null : (amount ?? this.amount),
      quantity: quantity ?? this.quantity,
      kind: kind ?? this.kind,
      rawText: rawText,
      // Any edit means the user has looked at the row, so it is no longer
      // suspicious.
      suspicious: suspicious ?? false,
      custom: custom,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'amount': amount,
    'quantity': quantity,
    'kind': kind.name,
    'rawText': rawText,
    'suspicious': suspicious,
    'custom': custom,
  };

  static ReceiptLine fromJson(Map<String, dynamic> j) => ReceiptLine(
    id: j['id'] as String,
    description: j['description'] as String? ?? '',
    amount: (j['amount'] as num?)?.toDouble(),
    quantity: (j['quantity'] as num?)?.toInt() ?? 1,
    kind: LineKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => LineKind.item,
    ),
    rawText: j['rawText'] as String? ?? '',
    suspicious: j['suspicious'] as bool? ?? false,
    custom: j['custom'] as bool? ?? false,
  );
}

class ParsedReceipt {
  final List<ReceiptLine> lines;
  final double? subtotal;
  final double? tax;
  final double? total;

  /// True when the printed tax was added on top of the subtotal rather than
  /// already included in the item prices. See [taxIsAdditive] in the parser.
  final bool taxIsAdditive;

  const ParsedReceipt({
    required this.lines,
    this.subtotal,
    this.tax,
    this.total,
    this.taxIsAdditive = false,
  });

  Iterable<ReceiptLine> get items =>
      lines.where((l) => l.kind == LineKind.item);

  /// Rows that take part in the split: items, extras and discounts.
  List<ReceiptLine> get splitRows =>
      lines.where((l) => l.kind.isSplittable).toList();

  /// Items only. Extras and discounts are excluded because the printed
  /// subtotal they are checked against excludes them too.
  double get itemSum => items.fold(0.0, (sum, l) => sum + (l.amount ?? 0));

  /// Everything that gets distributed between people.
  double get splitSum => splitRows.fold(0.0, (sum, l) => sum + l.effective);

  /// What the arithmetic is checked against: the printed subtotal, or the
  /// printed total if no subtotal was found.
  double? get balanceTarget => subtotal ?? total;

  /// CORRECTION over the brief: the brief's `balances` returns false when no
  /// target was found, which makes the UI shout "doesn't add up" at a receipt
  /// whose subtotal simply was not read. Callers must check this first and
  /// hide the banner entirely when it is false.
  bool get hasBalanceTarget => balanceTarget != null;

  /// Does the arithmetic hold? If false, OCR misread something and the
  /// correction UI should say so loudly rather than quietly being wrong.
  /// Tolerance absorbs rounding, not errors.
  bool get balances {
    final target = balanceTarget;
    if (target == null) return false;
    return (itemSum - target).abs() < 0.02;
  }
}
