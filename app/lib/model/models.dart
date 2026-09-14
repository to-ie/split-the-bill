import '../parsing/receipt.dart';

class Friend {
  final String id;
  final String name;
  final int color;

  const Friend({required this.id, required this.name, required this.color});

  bool get isYou => id == 'you';

  Friend copyWith({String? name}) =>
      Friend(id: id, name: name ?? this.name, color: color);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};

  static Friend fromJson(Map<String, dynamic> j) => Friend(
    id: j['id'] as String,
    name: j['name'] as String,
    color: (j['color'] as num).toInt(),
  );
}

/// A payment one person made to another. Frozen at the moment it is
/// recorded; see LOGIC.md section 8.
///
/// This is the only record of anything being paid off. There used to be a
/// second one - a "settled" flag on a receipt - and the two could not be kept
/// consistent with each other, so the flag is gone and every clearing of a
/// debt is a payment between two people.
class Settlement {
  final String from;
  final String to;
  final int cents;

  const Settlement({required this.from, required this.to, required this.cents});

  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'cents': cents};

  static Settlement fromJson(Map<String, dynamic> j) => Settlement(
    from: j['from'] as String,
    to: j['to'] as String,
    cents: (j['cents'] as num).toInt(),
  );
}

/// A receipt as stored in a group.
///
/// CORRECTION over the prototype: the prototype kept one live draft plus a
/// list of frozen, view-only receipts, and could not edit a logged one.
/// Here every receipt keeps its lines and assignments, so any receipt can be
/// reopened and re-split. Shares are recomputed from the lines rather than
/// frozen, which means editing an old receipt correctly re-opens the group
/// aggregation. Recorded settlements stay frozen regardless, per LOGIC.md.
class Receipt {
  final String id;
  final String name;

  /// Free-text comment shown before the date, e.g. "Dinner".
  final String comment;
  final String date;
  final String paidBy;
  final List<ReceiptLine> lines;

  /// line id -> friend ids sharing it.
  final Map<String, List<String>> assign;

  /// The party for this receipt: who was present, in display order.
  final List<String> party;

  /// Printed figures, kept for the balance banner and the receipt footer.
  final double? printedSubtotal;
  final double? printedTotal;

  const Receipt({
    required this.id,
    required this.name,
    this.comment = '',
    required this.date,
    required this.paidBy,
    required this.lines,
    required this.assign,
    required this.party,
    this.printedSubtotal,
    this.printedTotal,
  });

  List<ReceiptLine> get splitRows =>
      lines.where((l) => l.kind.isSplittable).toList();

  int _sumOf(LineKind kind) => lines
      .where((l) => l.kind == kind)
      .fold(0, (s, l) => s + (l.effective * 100).round());

  /// What the lines currently add up to, by kind. These are what the user is
  /// editing, as opposed to [printedSubtotal] and [printedTotal], which are
  /// what OCR read off the paper.
  int get itemsCents => _sumOf(LineKind.item);
  int get extrasCents => _sumOf(LineKind.adjustment);
  int get discountsCents => _sumOf(LineKind.discount);

  /// "What the bill came to", including rows nobody has claimed.
  int get grandCents =>
      splitRows.fold(0, (s, l) => s + (l.effective * 100).round());

  String get sub {
    final parts = <String>[];
    if (comment.trim().isNotEmpty) parts.add(comment.trim());
    parts.add(date);
    return parts.join(' · ');
  }

  Receipt copyWith({
    String? name,
    String? comment,
    String? date,
    String? paidBy,
    List<ReceiptLine>? lines,
    Map<String, List<String>>? assign,
    List<String>? party,
    double? printedSubtotal,
    double? printedTotal,
  }) => Receipt(
    id: id,
    name: name ?? this.name,
    comment: comment ?? this.comment,
    date: date ?? this.date,
    paidBy: paidBy ?? this.paidBy,
    lines: lines ?? this.lines,
    assign: assign ?? this.assign,
    party: party ?? this.party,
    printedSubtotal: printedSubtotal ?? this.printedSubtotal,
    printedTotal: printedTotal ?? this.printedTotal,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'comment': comment,
    'date': date,
    'paidBy': paidBy,
    'lines': lines.map((l) => l.toJson()).toList(),
    'assign': assign,
    'party': party,
    'printedSubtotal': printedSubtotal,
    'printedTotal': printedTotal,
  };

  static Receipt fromJson(Map<String, dynamic> j) => Receipt(
    id: j['id'] as String,
    name: j['name'] as String,
    comment: j['comment'] as String? ?? '',
    date: j['date'] as String? ?? '',
    paidBy: j['paidBy'] as String? ?? 'you',
    lines: (j['lines'] as List)
        .map((e) => ReceiptLine.fromJson(e as Map<String, dynamic>))
        .toList(),
    assign: (j['assign'] as Map).map(
      (k, v) => MapEntry(k as String, (v as List).cast<String>()),
    ),
    party: (j['party'] as List?)?.cast<String>() ?? const ['you'],
    printedSubtotal: (j['printedSubtotal'] as num?)?.toDouble(),
    printedTotal: (j['printedTotal'] as num?)?.toDouble(),
  );
}

class Group {
  final String id;
  final String name;

  /// null means "follow the app default currency".
  final String? currency;
  final bool archived;
  final List<Receipt> receipts;
  final List<Settlement> settlements;

  /// A one-off split is a group of one that never shows in the group list.
  final bool oneOff;

  const Group({
    required this.id,
    required this.name,
    this.currency,
    this.archived = false,
    required this.receipts,
    this.settlements = const [],
    this.oneOff = false,
  });

  /// Everyone who appears in any receipt's party, in first-seen order.
  List<String> get members {
    final seen = <String>[];
    for (final r in receipts) {
      for (final m in r.party) {
        if (!seen.contains(m)) seen.add(m);
      }
    }
    if (seen.isEmpty) seen.add('you');
    return seen;
  }

  Group copyWith({
    String? name,
    String? currency,
    bool clearCurrency = false,
    bool? archived,
    List<Receipt>? receipts,
    List<Settlement>? settlements,
  }) => Group(
    id: id,
    name: name ?? this.name,
    currency: clearCurrency ? null : (currency ?? this.currency),
    archived: archived ?? this.archived,
    receipts: receipts ?? this.receipts,
    settlements: settlements ?? this.settlements,
    oneOff: oneOff,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'currency': currency,
    'archived': archived,
    'receipts': receipts.map((r) => r.toJson()).toList(),
    'settlements': settlements.map((s) => s.toJson()).toList(),
    'oneOff': oneOff,
  };

  static Group fromJson(Map<String, dynamic> j) => Group(
    id: j['id'] as String,
    name: j['name'] as String,
    currency: j['currency'] as String?,
    archived: j['archived'] as bool? ?? false,
    receipts: (j['receipts'] as List)
        .map((e) => Receipt.fromJson(e as Map<String, dynamic>))
        .toList(),
    settlements: (j['settlements'] as List? ?? [])
        .map((e) => Settlement.fromJson(e as Map<String, dynamic>))
        .toList(),
    oneOff: j['oneOff'] as bool? ?? false,
  );
}

class AppSettings {
  final String myName;
  final bool dark;
  final String appCurrency;
  final List<String> currencies;
  final bool pinOn;

  /// Salted SHA-256 of the PIN, never the PIN itself.
  ///
  /// A four digit PIN has ten thousand possibilities, so this does not stop
  /// anyone who can read the file and wants to spend a second on it. What it
  /// does stop is the PIN being *disclosed* by anything that reads the store
  /// - a bug report, a file manager, a support request - which matters
  /// because people reuse the PIN that unlocks their phone and their bank
  /// card. The salt is per install, so two phones with the same PIN do not
  /// produce the same hash.
  final String pinHash;
  final String pinSalt;

  const AppSettings({
    this.myName = '',
    this.dark = false,
    this.appCurrency = '€',
    this.currencies = const ['€', '£', r'$'],
    this.pinOn = false,
    this.pinHash = '',
    this.pinSalt = '',
  });

  bool get hasPin => pinHash.isNotEmpty && pinSalt.isNotEmpty;

  AppSettings copyWith({
    String? myName,
    bool? dark,
    String? appCurrency,
    List<String>? currencies,
    bool? pinOn,
    String? pinHash,
    String? pinSalt,
  }) => AppSettings(
    myName: myName ?? this.myName,
    dark: dark ?? this.dark,
    appCurrency: appCurrency ?? this.appCurrency,
    currencies: currencies ?? this.currencies,
    pinOn: pinOn ?? this.pinOn,
    pinHash: pinHash ?? this.pinHash,
    pinSalt: pinSalt ?? this.pinSalt,
  );

  Map<String, dynamic> toJson() => {
    'myName': myName,
    'dark': dark,
    'appCurrency': appCurrency,
    'currencies': currencies,
    'pinOn': pinOn,
    'pinHash': pinHash,
    'pinSalt': pinSalt,
  };

  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
    myName: j['myName'] as String? ?? '',
    dark: j['dark'] as bool? ?? false,
    appCurrency: j['appCurrency'] as String? ?? '€',
    currencies:
        (j['currencies'] as List?)?.cast<String>() ?? const ['€', '£', r'$'],
    pinOn: j['pinOn'] as bool? ?? false,
    pinHash: j['pinHash'] as String? ?? '',
    pinSalt: j['pinSalt'] as String? ?? '',
  );
}

/// The currency catalogue from the design handoff, screen 12.
const currencyCatalogue = <(String, String)>[
  ('€', 'Euro'),
  ('£', 'British pound'),
  (r'$', 'US dollar'),
  ('CHF', 'Swiss franc'),
  ('¥', 'Yen'),
  ('kr', 'Krona'),
  ('zł', 'Złoty'),
  (r'C$', 'Canadian dollar'),
  (r'A$', 'Australian dollar'),
];

const friendPalette = <int>[
  0xFF10A374,
  0xFFE2A21B,
  0xFFD1603D,
  0xFF4A6FD1,
  0xFF8A5BC7,
  0xFFC24B7A,
];
