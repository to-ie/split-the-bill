import '../model/models.dart';
import 'aggregate.dart';

/// Money somebody has handed over that no longer answers to a debt.
///
/// A recorded payment is frozen on purpose: it is a thing that happened in
/// the real world, and an app that quietly rewrites it the moment a bill
/// changes is lying about the past. That was the flaw in the old "mark as
/// settled" flag, which could disagree with the payments and did.
///
/// The cost of keeping payments honest is that deleting or shrinking a bill
/// can leave somebody holding money for a debt that has gone. The arithmetic
/// is right - if Ben paid fifty towards a bill that turns out never to have
/// existed, he really is owed fifty back - but the group screen used to show
/// the balance move with nothing to explain it.
///
/// So the residue is named rather than absorbed. What it comes to, per
/// person, is what they paid out less whatever the bills alone left them
/// owing.
Map<String, int> overpaidBy(Group group) {
  final totals = aggregate(group, (id) => id);
  final nets = {for (final p in totals.people) p.friendId: p.netCents};

  // What each person has actually handed over, less anything handed back.
  final handedOver = <String, int>{};
  for (final s in group.settlements) {
    handedOver[s.from] = (handedOver[s.from] ?? 0) + s.cents;
    handedOver[s.to] = (handedOver[s.to] ?? 0) - s.cents;
  }

  final over = <String, int>{};
  handedOver.forEach((person, cash) {
    // Somebody who is up on the payments cannot have overpaid.
    if (cash <= 0) return;

    // Their position with the payments taken back out: what the bills on
    // their own leave them owing.
    final fromBills = (nets[person] ?? 0) + cash;
    final owed = fromBills > 0 ? fromBills : 0;

    final spare = cash - owed;
    if (spare > 0) over[person] = spare;
  });

  return over;
}

/// The payments that give [person] back what they are holding for nothing,
/// most recent first, each one returned by whoever actually received it.
///
/// Nothing is edited or removed: a refund is itself a payment, in the
/// opposite direction, and shows up in the list like any other. That keeps
/// the ledger append-only, which is the only reason its figures can be
/// trusted.
List<Settlement> refundsFor(Group group, String person) {
  var left = overpaidBy(group)[person] ?? 0;
  if (left <= 0) return const [];

  final refunds = <Settlement>[];
  for (var i = group.settlements.length - 1; i >= 0 && left > 0; i--) {
    final s = group.settlements[i];
    if (s.from != person) continue;

    final amount = s.cents < left ? s.cents : left;
    refunds.add(Settlement(from: s.to, to: person, cents: amount));
    left -= amount;
  }
  return refunds;
}

/// Hands back everything nobody owes any more.
///
/// Giving one person their money back can leave the person who returned it
/// holding money of their own for nothing, so this repeats until there is
/// none left. Each pass strictly reduces the amount unaccounted for, so it
/// ends; the counter is only there so that a bug cannot hang the app.
Group withOverpaymentsRefunded(Group group) {
  var g = group;
  for (var pass = 0; pass < 12; pass++) {
    final over = overpaidBy(g);
    if (over.isEmpty) return g;

    final refunds = <Settlement>[];
    for (final person in over.keys) {
      refunds.addAll(refundsFor(g, person));
    }
    if (refunds.isEmpty) return g;

    g = g.copyWith(settlements: [...g.settlements, ...refunds]);
  }
  return g;
}

/// What deleting [receiptId] would leave people holding, over and above
/// anything they are already holding now.
Map<String, int> overpaymentIfDeleted(Group group, String receiptId) {
  final before = overpaidBy(group);
  final after = overpaidBy(
    group.copyWith(
      receipts: group.receipts.where((r) => r.id != receiptId).toList(),
    ),
  );

  final raised = <String, int>{};
  after.forEach((person, cents) {
    if (cents > (before[person] ?? 0)) raised[person] = cents;
  });
  return raised;
}
