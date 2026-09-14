import '../model/models.dart';
import '../model/money.dart';
import '../parsing/receipt.dart';

/// One person's share of one line.
class ShareLine {
  final String lineId;
  final String description;
  final int cents;

  /// How many people shared the line. Rendered as "· ÷N" when > 1.
  final int splitBetween;

  const ShareLine({
    required this.lineId,
    required this.description,
    required this.cents,
    required this.splitBetween,
  });
}

/// What each person owes for one receipt, in cents.
class ReceiptShares {
  /// friend id -> total cents owed.
  final Map<String, int> per;

  /// friend id -> the lines making up their total.
  final Map<String, List<ShareLine>> lines;

  /// Sum of every split row, including rows nobody has claimed.
  final int grandCents;

  /// Sum of [per]. Differs from [grandCents] exactly when rows are unassigned.
  final int distributedCents;

  const ReceiptShares({
    required this.per,
    required this.lines,
    required this.grandCents,
    required this.distributedCents,
  });

  int get unassignedCents => grandCents - distributedCents;
  bool get hasUnassigned => unassignedCents.abs() > 1;
}

/// Per-receipt shares, LOGIC.md section 5.
///
/// share(P) = sum over split rows r where P is in assign[r] of eff(r)/|assign[r]|
///
/// Two departures from the spec, both deliberate:
///
///  1. Division happens in integer cents with largest-remainder allocation, so
///     the shares of a row always add back up to the row exactly. See
///     [allocate]. Without this the group aggregation invariant in section 7
///     cannot hold.
///
///  2. Assignees who are no longer in [party] are dropped before dividing.
///     LOGIC.md section 4 says removing someone from the party does not clean
///     up assignments and that shares are computed over party members only.
///     Dropping them before the division, rather than after, is what keeps the
///     row's shares summing to the row: if a row is assigned to three people
///     and one has left, the remaining two owe half each, not a third each
///     with a third going nowhere.
ReceiptShares computeShares(Receipt receipt, {List<String>? party}) {
  final members = party ?? receipt.party;
  final per = <String, int>{for (final m in members) m: 0};
  final lines = <String, List<ShareLine>>{for (final m in members) m: []};

  var grand = 0;
  var distributed = 0;

  for (final row in receipt.splitRows) {
    final cents = toCents(row.effective);
    grand += cents;

    final assignees = (receipt.assign[row.id] ?? const <String>[])
        .where(members.contains)
        .toList();
    if (assignees.isEmpty) continue;

    // Allocate in party order so the leftover penny lands predictably.
    assignees.sort((a, b) => members.indexOf(a).compareTo(members.indexOf(b)));

    final parts = allocate(cents, assignees.length);
    for (var i = 0; i < assignees.length; i++) {
      final who = assignees[i];
      per[who] = (per[who] ?? 0) + parts[i];
      lines[who]!.add(
        ShareLine(
          lineId: row.id,
          description: row.description.isEmpty ? 'Untitled' : row.description,
          cents: parts[i],
          splitBetween: assignees.length,
        ),
      );
      distributed += parts[i];
    }
  }

  return ReceiptShares(
    per: per,
    lines: lines,
    grandCents: grand,
    distributedCents: distributed,
  );
}

/// How many split rows have nobody on them.
int unassignedRowCount(Receipt receipt, List<String> party) {
  var n = 0;
  for (final row in receipt.splitRows) {
    final a = (receipt.assign[row.id] ?? const <String>[])
        .where(party.contains)
        .toList();
    if (a.isEmpty) n++;
  }
  return n;
}

/// Everything from the balance banner, LOGIC.md section 3.
class BalanceCheck {
  final bool hasTarget;
  final bool balanced;
  final double itemSum;
  final double target;

  const BalanceCheck({
    required this.hasTarget,
    required this.balanced,
    required this.itemSum,
    required this.target,
  });
}

/// CORRECTION over the brief: when no subtotal and no total were read, the
/// brief's `balances` returns false, which would put a red "doesn't add up"
/// banner on a receipt whose subtotal simply was not legible. There is nothing
/// to check against, so there is nothing to say: [hasTarget] is false and the
/// banner is hidden.
BalanceCheck checkBalance(Receipt receipt) {
  final itemSum = receipt.lines
      .where((l) => l.kind == LineKind.item)
      .fold(0.0, (s, l) => s + (l.amount ?? 0));

  final target = receipt.printedSubtotal ?? receipt.printedTotal;
  if (target == null) {
    return BalanceCheck(
      hasTarget: false,
      balanced: false,
      itemSum: itemSum,
      target: 0,
    );
  }
  return BalanceCheck(
    hasTarget: true,
    balanced: (itemSum - target).abs() < 0.02,
    itemSum: itemSum,
    target: target,
  );
}
