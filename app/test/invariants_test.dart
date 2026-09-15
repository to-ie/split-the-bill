import 'dart:convert';
import 'dart:math';

import 'package:bill/logic/aggregate.dart';
import 'package:bill/logic/overpayment.dart';
import 'package:bill/logic/receipt_payments.dart';
import 'package:bill/logic/settle_up.dart';
import 'package:bill/logic/shares.dart';
import 'package:bill/model/models.dart';
import 'package:bill/model/money.dart';
import 'package:bill/parsing/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

/// The properties that must hold for every group the app can ever be in,
/// checked against deliberately hostile data rather than tidy examples.
///
/// Every screen in the app is a view onto these numbers. If one of these
/// breaks, somebody is told they owe money they do not owe.

ReceiptLine line(
  String id,
  String d,
  double a, {
  LineKind kind = LineKind.item,
}) => ReceiptLine(id: id, description: d, amount: a, kind: kind, rawText: d);

// ----------------------------------------------------------- the invariants

void checkGroup(Group g, String because) {
  final totals = aggregate(g, (id) => id);

  // 1. Money is never created or destroyed.
  expect(
    totals.people.fold(0, (s, p) => s + p.netCents),
    0,
    reason: 'nets must sum to zero: $because',
  );

  // 2. Settling up clears exactly the debts and no more.
  final after = {for (final p in totals.people) p.friendId: p.netCents};
  for (final t in totals.transfers) {
    expect(t.cents, greaterThan(0), reason: 'a transfer of nothing: $because');
    expect(t.from, isNot(t.to), reason: 'paying yourself: $because');
    after[t.from] = (after[t.from] ?? 0) - t.cents;
    after[t.to] = (after[t.to] ?? 0) + t.cents;
  }
  for (final e in after.entries) {
    expect(e.value, 0, reason: 'settle-up left ${e.key} adrift: $because');
  }

  // 3. Per receipt, the shares add up to what was handed out.
  for (final r in g.receipts) {
    final s = computeShares(r);
    expect(
      s.per.values.fold(0, (a, b) => a + b),
      s.distributedCents,
      reason: 'shares do not sum: $because',
    );
    expect(
      s.distributedCents + s.unassignedCents,
      s.grandCents,
      reason: 'a row went missing: $because',
    );
  }

  // 4. Badges never claim more than is true.
  final payments = receiptPayments(g);
  final anyPayment = g.settlements.isNotEmpty;
  for (final r in g.receipts) {
    final p = payments[r.id]!;
    expect(p.paidCents, lessThanOrEqualTo(p.owedCents),
        reason: 'more paid than owed on ${r.id}: $because');
    expect(p.cashCents, lessThanOrEqualTo(p.paidCents),
        reason: 'cash exceeds credit on ${r.id}: $because');
    expect(p.paidCents, greaterThanOrEqualTo(0));
    expect(p.cashCents, greaterThanOrEqualTo(0));

    if (!anyPayment && !totals.allSquare) {
      expect(
        p.progress,
        PaymentProgress.none,
        reason: 'a badge with nothing paid on ${r.id}: $because',
      );
    }
    if (p.progress == PaymentProgress.partial) {
      expect(p.cashCents, greaterThan(0),
          reason: 'part paid without money moving: $because');
    }
  }

  // 5. Nobody has handed back more than they were ever given.
  for (final person in {...g.members, ...g.settlements.map((s) => s.from)}) {
    final got = g.settlements
        .where((s) => !s.refund && s.to == person)
        .fold(0, (a, s) => a + s.cents);
    final gave = g.settlements
        .where((s) => s.refund && s.from == person)
        .fold(0, (a, s) => a + s.cents);
    expect(gave, lessThanOrEqualTo(got),
        reason: '$person handed back more than received: $because');
  }

  // 6. Refunding always settles the residue, and never runs away.
  final healed = withOverpaymentsRefunded(g);
  expect(overpaidBy(healed), isEmpty,
      reason: 'refunding did not clear: $because');
  expect(
    healed.settlements.length,
    greaterThanOrEqualTo(g.settlements.length),
    reason: 'the ledger shrank: $because',
  );
  for (var i = 0; i < g.settlements.length; i++) {
    expect(healed.settlements[i].cents, g.settlements[i].cents,
        reason: 'history was rewritten: $because');
  }
  checkNetsOnly(healed, '$because (after refunding)');

  // 7. The deletion preview tells the truth, for every bill.
  for (final r in g.receipts) {
    final promised = {for (final s in shiftIfDeleted(g, r.id)) s.person: s.after};
    final actual = aggregate(
      g.copyWith(receipts: g.receipts.where((x) => x.id != r.id).toList()),
      (id) => id,
    );
    final real = {for (final p in actual.people) p.friendId: p.netCents};
    promised.forEach((who, net) {
      expect(real[who] ?? 0, net,
          reason: 'the delete warning lied about $who: $because');
    });
  }

  // 8. It all survives being written down and read back.
  final round = Group.fromJson(
    jsonDecode(jsonEncode(g.toJson())) as Map<String, dynamic>,
  );
  expect(round.settlements.length, g.settlements.length);
  for (var i = 0; i < g.settlements.length; i++) {
    expect(round.settlements[i].refund, g.settlements[i].refund,
        reason: 'the refund flag did not survive: $because');
  }
  expect(
    aggregate(round, (id) => id).people.fold(0, (s, p) => s + p.netCents),
    0,
  );
}

void checkNetsOnly(Group g, String because) {
  final t = aggregate(g, (id) => id);
  expect(t.people.fold(0, (s, p) => s + p.netCents), 0,
      reason: 'nets must sum to zero: $because');
}

// --------------------------------------------------------------- generators

Receipt randomReceipt(Random rng, String id, List<String> people) {
  final party = people.where((_) => rng.nextInt(10) > 0).toList();
  if (party.isEmpty) party.add(people.first);

  final lines = <ReceiptLine>[];
  final assign = <String, List<String>>{};
  final rows = 1 + rng.nextInt(6);

  for (var i = 0; i < rows; i++) {
    final kind = switch (rng.nextInt(10)) {
      0 => LineKind.adjustment,
      1 => LineKind.discount,
      _ => LineKind.item,
    };
    // Awkward amounts on purpose, including zero and a very large one.
    final amount = switch (rng.nextInt(20)) {
      0 => 0.0,
      1 => 9999.99,
      2 => 0.01,
      _ => (rng.nextInt(20000)) / 100,
    };
    lines.add(line('l$i', 'Row $i', kind == LineKind.discount ? -amount : amount,
        kind: kind));

    // Some rows go to nobody, some to everybody, some to a random few.
    final who = party.where((_) => rng.nextBool()).toList();
    if (rng.nextInt(8) != 0) assign['l$i'] = who;
  }

  return Receipt(
    id: id,
    name: 'Bill $id',
    date: '1 Jan',
    // Sometimes the payer is not even in the party: the app allows it.
    paidBy: rng.nextInt(12) == 0
        ? people[rng.nextInt(people.length)]
        : party[rng.nextInt(party.length)],
    party: party,
    lines: lines,
    assign: assign,
  );
}

void main() {
  group('allocate', () {
    test('splits exactly, whatever the remainder', () {
      for (var total = -500; total <= 500; total++) {
        for (var n = 1; n <= 7; n++) {
          final parts = allocate(total, n);
          expect(parts, hasLength(n));
          expect(parts.fold(0, (a, b) => a + b), total,
              reason: '$total among $n');
          // No part is more than a penny from any other.
          final lo = parts.reduce(min);
          final hi = parts.reduce(max);
          expect(hi - lo, lessThanOrEqualTo(1), reason: '$total among $n');
        }
      }
    });

    test('nobody to split between', () {
      expect(allocate(100, 0), isEmpty);
    });
  });

  group('degenerate groups', () {
    test('an empty group', () {
      checkGroup(const Group(id: 'g', name: 'x', receipts: []), 'empty');
    });

    test('a group with settlements but no bills', () {
      checkGroup(
        const Group(
          id: 'g',
          name: 'x',
          receipts: [],
          settlements: [Settlement(from: 'a', to: 'b', cents: 500)],
        ),
        'settlements only',
      );
    });

    test('a bill of nothing', () {
      checkGroup(
        Group(
          id: 'g',
          name: 'x',
          receipts: [
            Receipt(
              id: 'r',
              name: 'n',
              date: 'd',
              paidBy: 'you',
              party: const ['you', 'a'],
              lines: [line('l', 'free', 0)],
              assign: const {
                'l': ['you', 'a'],
              },
            ),
          ],
        ),
        'zero total',
      );
    });

    test('nothing assigned to anybody', () {
      final g = Group(
        id: 'g',
        name: 'x',
        receipts: [
          Receipt(
            id: 'r',
            name: 'n',
            date: 'd',
            paidBy: 'you',
            party: const ['you', 'a'],
            lines: [line('l', 'dinner', 30)],
            assign: const {},
          ),
        ],
      );
      checkGroup(g, 'wholly unassigned');
      // Everybody is square, but the bill is not "Paid" - there is nothing
      // on it to pay.
      expect(receiptPayments(g)['r']!.progress, PaymentProgress.none);
    });

    test('a discount bigger than the bill', () {
      checkGroup(
        Group(
          id: 'g',
          name: 'x',
          receipts: [
            Receipt(
              id: 'r',
              name: 'n',
              date: 'd',
              paidBy: 'you',
              party: const ['you', 'a'],
              lines: [
                line('l1', 'food', 10),
                line('l2', 'voucher', -50, kind: LineKind.discount),
              ],
              assign: const {
                'l1': ['you', 'a'],
                'l2': ['you', 'a'],
              },
            ),
          ],
        ),
        'negative bill',
      );
    });

    test('a payer who was not at the table', () {
      checkGroup(
        Group(
          id: 'g',
          name: 'x',
          receipts: [
            Receipt(
              id: 'r',
              name: 'n',
              date: 'd',
              paidBy: 'ghost',
              party: const ['a', 'b'],
              lines: [line('l', 'dinner', 40)],
              assign: const {
                'l': ['a', 'b'],
              },
            ),
          ],
        ),
        'absent payer',
      );
    });

    test('settlements naming people who were never here', () {
      checkGroup(
        Group(
          id: 'g',
          name: 'x',
          receipts: [
            Receipt(
              id: 'r',
              name: 'n',
              date: 'd',
              paidBy: 'a',
              party: const ['a', 'b'],
              lines: [line('l', 'dinner', 40)],
              assign: const {
                'l': ['a', 'b'],
              },
            ),
          ],
          settlements: [
            Settlement(from: 'nobody', to: 'noone', cents: 999),
          ],
        ),
        'strangers settling',
      );
    });

    test('assignments pointing at rows that no longer exist', () {
      checkGroup(
        Group(
          id: 'g',
          name: 'x',
          receipts: [
            Receipt(
              id: 'r',
              name: 'n',
              date: 'd',
              paidBy: 'a',
              party: const ['a', 'b'],
              lines: [line('l1', 'dinner', 40)],
              assign: const {
                'l1': ['a', 'b'],
                'gone': ['a'],
              },
            ),
          ],
        ),
        'stale assignment',
      );
    });

    test('a refund with no payment behind it', () {
      checkNetsOnly(
        const Group(
          id: 'g',
          name: 'x',
          receipts: [],
          settlements: [Settlement(from: 'a', to: 'b', cents: 500, refund: true)],
        ),
        'orphan refund',
      );
    });

    test('very large money', () {
      checkGroup(
        Group(
          id: 'g',
          name: 'x',
          receipts: [
            for (var i = 0; i < 20; i++)
              Receipt(
                id: 'r$i',
                name: 'n',
                date: 'd',
                paidBy: 'a',
                party: const ['a', 'b', 'c'],
                lines: [line('l', 'huge', 999999.99)],
                assign: const {
                  'l': ['a', 'b', 'c'],
                },
              ),
          ],
        ),
        'twenty million',
      );
    });
  });

  test('fuzzing: every invariant, on hostile groups', () {
    final rng = Random(20260916);

    for (var round = 0; round < 400; round++) {
      final people = ['you', 'a', 'b', 'c', 'd']
          .take(1 + rng.nextInt(5))
          .toList();
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          for (var i = 0; i < rng.nextInt(5); i++)
            randomReceipt(rng, 'r$i', people),
        ],
      );

      checkGroup(g, 'round $round, fresh');

      // Settle some of what is suggested, sometimes in part, sometimes twice.
      for (final t in aggregate(g, (id) => id).transfers) {
        if (rng.nextInt(3) == 0) continue;
        final part = rng.nextBool() ? t.cents : 1 + rng.nextInt(t.cents);
        g = g.copyWith(
          settlements: [
            ...g.settlements,
            Settlement(from: t.from, to: t.to, cents: part),
          ],
        );
      }
      checkGroup(g, 'round $round, settled');

      // Then start pulling bills out from under it.
      final ids = g.receipts.map((r) => r.id).toList()..shuffle(rng);
      for (final id in ids) {
        g = g.copyWith(
          receipts: g.receipts.where((r) => r.id != id).toList(),
        );
        if (rng.nextBool()) g = withOverpaymentsRefunded(g);
        checkGroup(g, 'round $round, after deleting $id');
      }
    }
  });

  test('fuzzing: settle-up never suggests more payments than it needs', () {
    final rng = Random(7);
    for (var round = 0; round < 2000; round++) {
      final n = 2 + rng.nextInt(6);
      final nets = <String, int>{};
      var running = 0;
      for (var i = 0; i < n - 1; i++) {
        final v = rng.nextInt(20000) - 10000;
        nets['p$i'] = v;
        running += v;
      }
      nets['p${n - 1}'] = -running;

      final transfers = settleUp(nets);
      final owing = nets.values.where((v) => v > 0).length;
      final owed = nets.values.where((v) => v < 0).length;
      if (owing + owed > 0) {
        expect(transfers.length, lessThanOrEqualTo(owing + owed - 1),
            reason: 'too many payments for $nets');
      }
      final after = {...nets};
      for (final t in transfers) {
        after[t.from] = after[t.from]! - t.cents;
        after[t.to] = after[t.to]! + t.cents;
      }
      for (final v in after.values) {
        expect(v, 0, reason: 'settle-up did not square $nets');
      }
    }
  });
}
