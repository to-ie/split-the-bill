import '../model/models.dart';
import 'settle_up.dart';
import 'shares.dart';

/// One line in a person's itemised group breakdown.
class LedgerLine {
  final String label;
  final int cents;

  /// What that line is made of: for a bill, the items this person actually
  /// had. Without these the group summary shows a figure per bill and leaves
  /// everyone to take on trust that it is not just the total divided by the
  /// number of people at the table.
  final List<LedgerLine> detail;

  const LedgerLine(this.label, this.cents, {this.detail = const []});
}

/// Where one person stands across a whole group.
class PersonNet {
  final String friendId;

  /// What they owe for their share of the bills.
  final int shareCents;

  /// What they have put in: bills they paid, plus debts they have settled.
  final int paidCents;

  final List<LedgerLine> ledger;

  const PersonNet({
    required this.friendId,
    required this.shareCents,
    required this.paidCents,
    required this.ledger,
  });

  int get netCents => shareCents - paidCents;

  bool get isSquare => netCents.abs() <= 0;
  bool get owes => netCents > 0;
  bool get getsBack => netCents < 0;
}

class GroupTotals {
  final List<PersonNet> people;
  final List<Transfer> transfers;

  /// What the group has spent in total, including amounts nobody has
  /// claimed yet.
  final int spentCents;

  /// What is still to be handed over: the sum of everything everybody owes,
  /// after the payments already recorded. Zero when the group is square.
  ///
  /// This is the figure the group and home screens lead with. Showing the
  /// total spent there meant a group that had been fully settled still
  /// displayed a large number, as though money were outstanding.
  final int outstandingCents;

  /// Unassigned money, per receipt, for the amber warning.
  final List<(Receipt, int)> unassigned;

  const GroupTotals({
    required this.people,
    required this.transfers,
    required this.spentCents,
    required this.outstandingCents,
    required this.unassigned,
  });

  bool get allSquare => people.every((p) => p.isSquare);
}

/// The invariant that matters: the payer of a receipt is credited with that
/// receipt's DISTRIBUTED total - the sum of the shares actually handed out -
/// and not with its face total. While rows are unassigned the two differ, and
/// crediting the face total would mean the nets no longer sum to zero, which
/// shows up to the user as money appearing from nowhere.
///
/// Because shares are allocated in integer cents (see [allocate]), the nets
/// here sum to exactly zero rather than approximately zero.
///
/// Group aggregation, LOGIC.md section 7.
///
/// Every receipt counts, and the only record of anything being paid off is a
/// payment from one person to another. There was briefly a second mechanism -
/// a "settled" flag that excluded a receipt from the sums - and the two could
/// not be kept consistent: marking a bill settled after everyone had paid for
/// it inverted the whole group, because the payments that cleared its debts
/// stayed in the ledger after the debts themselves had gone.
GroupTotals aggregate(Group group, String Function(String id) nameOf) {
  final live = group.receipts;

  final share = <String, int>{};
  final paid = <String, int>{};
  final ledger = <String, List<LedgerLine>>{};

  void add(Map<String, int> m, String k, int v) => m[k] = (m[k] ?? 0) + v;
  void note(
    String who,
    String label,
    int cents, {
    List<LedgerLine> detail = const [],
  }) => (ledger[who] ??= []).add(LedgerLine(label, cents, detail: detail));

  var spent = 0;
  final unassigned = <(Receipt, int)>[];

  for (final r in live) {
    final shares = computeShares(r);
    spent += r.grandCents;
    if (shares.hasUnassigned) unassigned.add((r, shares.unassignedCents));

    shares.per.forEach((who, cents) {
      if (cents == 0) return;
      add(share, who, cents);
      note(
        who,
        r.name,
        cents,
        detail: [
          for (final l in shares.lines[who] ?? const <ShareLine>[])
            LedgerLine(
              l.splitBetween > 1
                  ? '${l.description} · ÷${l.splitBetween}'
                  : l.description,
              l.cents,
            ),
        ],
      );
    });

    // The invariant.
    add(paid, r.paidBy, shares.distributedCents);
    if (shares.distributedCents != 0) {
      note(r.paidBy, 'Paid ${r.name}', -shares.distributedCents);
    }
  }

  // Recorded settlements. A payment from A to B means A has put money in and
  // B has taken money out, so it moves both nets towards zero.
  for (final s in group.settlements) {
    add(paid, s.from, s.cents);
    add(paid, s.to, -s.cents);
    if (s.refund) {
      note(s.from, 'Handed back to ${nameOf(s.to)}', -s.cents);
      note(s.to, 'Given back by ${nameOf(s.from)}', s.cents);
    } else {
      note(s.from, 'Settled up with ${nameOf(s.to)}', -s.cents);
      note(s.to, 'Received from ${nameOf(s.from)}', s.cents);
    }
  }

  final everyone = <String>{...share.keys, ...paid.keys}.toList();
  // Stable display order: group order first, then anyone else.
  final order = group.members;
  everyone.sort((a, b) {
    final ia = order.indexOf(a), ib = order.indexOf(b);
    return (ia == -1 ? 999 : ia).compareTo(ib == -1 ? 999 : ib);
  });

  final people = everyone
      .map(
        (id) => PersonNet(
          friendId: id,
          shareCents: share[id] ?? 0,
          paidCents: paid[id] ?? 0,
          ledger: ledger[id] ?? const [],
        ),
      )
      .toList();

  final nets = {for (final p in people) p.friendId: p.netCents};

  return GroupTotals(
    people: people,
    transfers: settleUp(nets),
    spentCents: spent,
    outstandingCents: people.fold(
      0,
      (s, p) => s + (p.netCents > 0 ? p.netCents : 0),
    ),
    unassigned: unassigned,
  );
}
