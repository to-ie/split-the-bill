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

  // Two different quantities, and conflating them was a bug.
  //
  // `paidDown` is what a person is out of pocket from settling: what they
  // handed over to clear a debt, less everything that has come back to them.
  // Money they *returned* to somebody else is not them paying a debt down,
  // and counting it as such made a person who had handed money back look as
  // though they had overpaid - so the app offered to refund them money they
  // had never paid.
  //
  // `settled` is every movement, refunds included, and is only used to undo
  // the settlements and recover what the bills alone say.
  final paidDown = <String, int>{};
  final settled = <String, int>{};

  for (final s in group.settlements) {
    settled[s.from] = (settled[s.from] ?? 0) + s.cents;
    settled[s.to] = (settled[s.to] ?? 0) - s.cents;

    // Money arriving reduces what a person is out of pocket, however it
    // arrives. Money leaving only counts when it was a debt being paid: money
    // handed back is a return, not a payment.
    paidDown[s.to] = (paidDown[s.to] ?? 0) - s.cents;
    if (!s.refund) {
      paidDown[s.from] = (paidDown[s.from] ?? 0) + s.cents;
    }
  }

  final over = <String, int>{};
  paidDown.forEach((person, paid) {
    // Somebody who has handed nothing over cannot have overpaid.
    if (paid <= 0) return;

    // Their position with every settlement taken back out: what the bills on
    // their own leave them owing.
    final fromBills = (nets[person] ?? 0) + (settled[person] ?? 0);
    final owed = fromBills > 0 ? fromBills : 0;

    final spare = paid - owed;
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

  final totals = aggregate(group, (id) => id);

  // How much of what this person paid has already come back, and from whom.
  //
  // Deleting a second bill used to reverse the same payment over again: each
  // pass walked the payments from newest and took what it needed, with no
  // memory of what an earlier pass had already handed back. The money then
  // came from whoever happened to be newest rather than from whoever was
  // actually holding it, and somebody ended up having returned more than they
  // were ever given.
  final alreadyBack = <String, int>{};
  for (final s in group.settlements) {
    if (s.refund && s.to == person) {
      alreadyBack[s.from] = (alreadyBack[s.from] ?? 0) + s.cents;
    }
  }

  // Who to ask for it back.
  //
  // Walking the payments newest-first reverses whichever was most recent,
  // which is not the same as reversing the one that is now unowed. If you
  // paid Ben for a taxi on Monday and Cara for dinner on Tuesday, and the
  // taxi is then deleted, it is Ben holding money for nothing - but recency
  // picks Cara, who is square, and leaves Ben with the taxi money.
  //
  // After the deletion the ledger already knows: whoever is holding money
  // they are not owed has a positive net. So prefer those, most over-credited
  // first, and fall back to newest-first only to break ties.
  final nets = {for (final p in totals.people) p.friendId: p.netCents};
  final order = List.generate(group.settlements.length, (i) => i)
    ..sort((a, b) {
      final sa = group.settlements[a];
      final sb = group.settlements[b];
      final ca = (nets[sa.to] ?? 0) > 0 ? (nets[sa.to] ?? 0) : 0;
      final cb = (nets[sb.to] ?? 0) > 0 ? (nets[sb.to] ?? 0) : 0;
      if (ca != cb) return cb.compareTo(ca);
      return b.compareTo(a);
    });

  final refunds = <Settlement>[];
  for (final i in order) {
    if (left <= 0) break;
    final s = group.settlements[i];
    if (s.from != person) continue;

    // Never unwind a refund. Reversing money that was already given back
    // would send it round in a circle and read as a payment nobody made.
    if (s.refund) continue;

    // Whatever has come back from this person already cancels the newest of
    // what was paid to them, so walk it off before reversing any more.
    var available = s.cents;
    final back = alreadyBack[s.to] ?? 0;
    if (back > 0) {
      final used = back < available ? back : available;
      available -= used;
      alreadyBack[s.to] = back - used;
    }
    if (available <= 0) continue;

    final amount = available < left ? available : left;
    refunds.add(
      Settlement(from: s.to, to: person, cents: amount, refund: true),
    );
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

/// Hands back only what these particular people are holding for nothing,
/// and whatever that in turn leaves somebody else holding.
///
/// Deleting a bill used to sweep up every outstanding overpayment in the
/// group, including ones the user had already been offered and declined -
/// while the button named only the amount this deletion had created. The
/// label and the action have to move the same money.
Group withOverpaymentsRefundedFor(Group group, Set<String> people) {
  var g = group;
  var chasing = {...people};

  for (var pass = 0; pass < 12; pass++) {
    final over = overpaidBy(g);
    final due = chasing.where((p) => (over[p] ?? 0) > 0).toList();
    if (due.isEmpty) return g;

    final refunds = <Settlement>[];
    for (final person in due) {
      refunds.addAll(refundsFor(g, person));
    }
    if (refunds.isEmpty) return g;

    g = g.copyWith(settlements: [...g.settlements, ...refunds]);
    // Giving money back can leave the person who gave it holding money of
    // their own for nothing.
    chasing = {...chasing, ...refunds.map((r) => r.from)};
  }
  return g;
}

/// Where one person stands before and after a bill is deleted.
class BalanceShift {
  final String person;

  /// Positive means they owe; negative means they are owed. Both are nets, in
  /// the same sense as [PersonNet.netCents].
  final int before;
  final int after;

  const BalanceShift({
    required this.person,
    required this.before,
    required this.after,
  });
}

/// What deleting [receiptId] would do to everybody's balance.
///
/// This replaces an earlier warning that named the people who had "settled
/// against this bill". Nobody ever settles against a bill: a payment clears a
/// net position across the whole group, and saying otherwise claimed a
/// precision the ledger does not have. Worse, it described only the people
/// left holding money and said nothing about the larger change - the person
/// who fronted the bill losing the credit for it, which is what usually moves
/// the most.
///
/// So the question the user is actually asking - what will this do? - is
/// answered directly, for everyone it touches.
List<BalanceShift> shiftIfDeleted(Group group, String receiptId) {
  final now = aggregate(group, (id) => id);
  final then = aggregate(
    group.copyWith(
      receipts: group.receipts.where((r) => r.id != receiptId).toList(),
    ),
    (id) => id,
  );

  final before = {for (final p in now.people) p.friendId: p.netCents};
  final after = {for (final p in then.people) p.friendId: p.netCents};

  final shifts = <BalanceShift>[];
  for (final person in {...before.keys, ...after.keys}) {
    final was = before[person] ?? 0;
    final will = after[person] ?? 0;
    if (was == will) continue;
    shifts.add(BalanceShift(person: person, before: was, after: will));
  }

  // Biggest movement first: that is the one somebody will argue about.
  shifts.sort(
    (a, b) =>
        (b.after - b.before).abs().compareTo((a.after - a.before).abs()),
  );
  return shifts;
}

/// What deleting [receiptId] would leave people holding for nothing, over and
/// above anything they are already holding now.
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
