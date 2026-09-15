import 'dart:math';

import 'package:bill/logic/aggregate.dart';
import 'package:bill/logic/overpayment.dart';
import 'package:bill/model/models.dart';
import 'package:bill/parsing/receipt.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptLine item(String id, String d, double a) => ReceiptLine(
  id: id,
  description: d,
  amount: a,
  kind: LineKind.item,
  rawText: d,
);

Receipt bill({
  required String id,
  required String paidBy,
  required double amount,
  required List<String> party,
}) => Receipt(
  id: id,
  name: 'Bill $id',
  date: '1 Jan',
  paidBy: paidBy,
  party: party,
  lines: [item('l1', 'Meal', amount)],
  assign: {'l1': party},
);

Map<String, int> nets(Group g) => {
  for (final p in aggregate(g, (id) => id).people) p.friendId: p.netCents,
};

void main() {
  const party = ['you', 'a', 'b'];

  group('what counts as overpaid', () {
    test('nothing is overpaid when the payments match the bills', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [bill(id: 'r1', paidBy: 'you', amount: 30, party: party)],
      );
      g = g.copyWith(
        settlements: const [
          Settlement(from: 'a', to: 'you', cents: 1000),
          Settlement(from: 'b', to: 'you', cents: 1000),
        ],
      );
      expect(overpaidBy(g), isEmpty);
    });

    test('deleting a settled bill leaves the payer of it in credit', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [bill(id: 'r1', paidBy: 'you', amount: 30, party: party)],
      );
      g = g.copyWith(
        settlements: const [Settlement(from: 'a', to: 'you', cents: 1000)],
      );
      expect(overpaidBy(g), isEmpty, reason: 'a owed exactly that');

      // And now the bill goes.
      final after = g.copyWith(receipts: const []);
      expect(overpaidBy(after), {'a': 1000});
    });

    test('shrinking a bill leaves only the difference in credit', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [bill(id: 'r1', paidBy: 'you', amount: 30, party: party)],
      );
      g = g.copyWith(
        settlements: const [Settlement(from: 'a', to: 'you', cents: 1000)],
      );
      // The bill was really 15, not 30, so a only ever owed 5.
      g = g.copyWith(
        receipts: [bill(id: 'r1', paidBy: 'you', amount: 15, party: party)],
      );
      expect(overpaidBy(g), {'a': 500});
    });

    test('being owed money for a bill you fronted is not overpaying', () {
      final g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [bill(id: 'r1', paidBy: 'you', amount: 30, party: party)],
      );
      expect(nets(g)['you'], -2000, reason: 'you are owed 20');
      expect(overpaidBy(g), isEmpty);
    });

    test('a refund received is not itself an overpayment', () {
      var g = Group(id: 'g', name: 'Trip', receipts: const []);
      g = g.copyWith(
        settlements: const [
          Settlement(from: 'a', to: 'you', cents: 1000),
          Settlement(from: 'you', to: 'a', cents: 1000),
        ],
      );
      expect(overpaidBy(g), isEmpty);
    });
  });

  group('handing it back', () {
    test('the refund goes back to whoever actually received it', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [bill(id: 'r1', paidBy: 'b', amount: 30, party: party)],
      );
      // a settles with b, who is the one who fronted the bill.
      g = g.copyWith(
        settlements: const [Settlement(from: 'a', to: 'b', cents: 1000)],
      );
      final after = g.copyWith(receipts: const []);

      final refunds = refundsFor(after, 'a');
      expect(refunds, hasLength(1));
      expect(refunds.single.from, 'b', reason: 'b is holding the money');
      expect(refunds.single.to, 'a');
      expect(refunds.single.cents, 1000);
    });

    test('refunding clears the credit and squares the group', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [bill(id: 'r1', paidBy: 'you', amount: 30, party: party)],
      );
      g = g.copyWith(
        settlements: const [
          Settlement(from: 'a', to: 'you', cents: 1000),
          Settlement(from: 'b', to: 'you', cents: 1000),
        ],
      );
      final after = withOverpaymentsRefunded(g.copyWith(receipts: const []));

      expect(overpaidBy(after), isEmpty);
      expect(aggregate(after, (id) => id).allSquare, isTrue);
      // Nothing was rewritten: the originals are still there, with the
      // reversals appended.
      expect(after.settlements.length, 4);
      expect(after.settlements.take(2), g.settlements);
    });

    test('a part payment is given back in part', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          bill(id: 'r1', paidBy: 'you', amount: 30, party: party),
          bill(id: 'r2', paidBy: 'you', amount: 30, party: party),
        ],
      );
      // a owes 10 on each and pays the lot.
      g = g.copyWith(
        settlements: const [Settlement(from: 'a', to: 'you', cents: 2000)],
      );
      // One of the two bills was a duplicate.
      final after = withOverpaymentsRefunded(
        g.copyWith(receipts: [g.receipts.first]),
      );

      expect(overpaidBy(after), isEmpty);
      expect(nets(after)['a'], 0);
      final back = after.settlements.skip(1).toList();
      expect(back, hasLength(1));
      expect(back.single.cents, 1000, reason: 'only half was unowed');
      expect(back.single.from, 'you');
    });

    test('deleting a bill nobody settled changes nothing', () {
      final g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          bill(id: 'r1', paidBy: 'you', amount: 30, party: party),
          bill(id: 'r2', paidBy: 'you', amount: 30, party: party),
        ],
      );
      final after = withOverpaymentsRefunded(
        g.copyWith(receipts: [g.receipts.first]),
      );
      expect(after.settlements, isEmpty);
    });
  });

  group('through the app', () {
    AppState appWith(Group g) {
      final app = AppState.ephemeral();
      app.friends = const [
        Friend(id: 'you', name: 'You', color: 1),
        Friend(id: 'a', name: 'Ana', color: 2),
        Friend(id: 'b', name: 'Ben', color: 3),
      ];
      app.groups = [g];
      return app;
    }

    test('the warning says who and how much before anything happens', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [bill(id: 'r1', paidBy: 'you', amount: 30, party: party)],
      );
      g = g.copyWith(
        settlements: const [Settlement(from: 'a', to: 'you', cents: 1000)],
      );
      final app = appWith(g);

      expect(app.creditIfReceiptDeleted('g', 'r1'), {'a': 1000});
      // And asking the question did not change anything.
      expect(app.groupById('g')!.receipts, hasLength(1));
      expect(app.groupById('g')!.settlements, hasLength(1));
    });

    test('deleting without refunding leaves the payment standing', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [bill(id: 'r1', paidBy: 'you', amount: 30, party: party)],
      );
      g = g.copyWith(
        settlements: const [Settlement(from: 'a', to: 'you', cents: 1000)],
      );
      final app = appWith(g);
      app.deleteReceipt('g', 'r1');

      expect(app.groupById('g')!.settlements, hasLength(1));
      expect(app.overpaymentsIn(app.groupById('g')!), {'a': 1000});
    });

    test('deleting with a refund squares it in one action', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [bill(id: 'r1', paidBy: 'you', amount: 30, party: party)],
      );
      g = g.copyWith(
        settlements: const [Settlement(from: 'a', to: 'you', cents: 1000)],
      );
      final app = appWith(g);
      app.deleteReceipt('g', 'r1', refund: true);

      final after = app.groupById('g')!;
      expect(app.overpaymentsIn(after), isEmpty);
      expect(aggregate(after, (id) => id).allSquare, isTrue);
      expect(after.settlements, hasLength(2));
    });

    test('handing it back later does the same thing', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [bill(id: 'r1', paidBy: 'you', amount: 30, party: party)],
      );
      g = g.copyWith(
        settlements: const [Settlement(from: 'a', to: 'you', cents: 1000)],
      );
      final app = appWith(g);
      app.deleteReceipt('g', 'r1');
      app.refundOverpayment('g', 'a');

      expect(app.overpaymentsIn(app.groupById('g')!), isEmpty);
      expect(aggregate(app.groupById('g')!, (id) => id).allSquare, isTrue);
    });
  });

  group('what deleting will do', () {
    test('warns that the payer loses the credit for fronting it', () {
      // The case the old warning missed completely: it named only people
      // holding money, and said nothing about the person who paid.
      const party = ['you', 'a', 'b'];
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          bill(id: 'r1', paidBy: 'you', amount: 30, party: party),
          bill(id: 'r2', paidBy: 'a', amount: 30, party: party),
          bill(id: 'r3', paidBy: 'b', amount: 60, party: party),
        ],
      );
      for (final t in aggregate(g, (id) => id).transfers) {
        g = g.copyWith(
          settlements: [
            ...g.settlements,
            Settlement(from: t.from, to: t.to, cents: t.cents),
          ],
        );
      }
      expect(aggregate(g, (id) => id).allSquare, isTrue);

      final shifts = shiftIfDeleted(g, 'r1');
      final you = shifts.firstWhere((s) => s.person == 'you');
      expect(you.before, 0);
      expect(you.after, 2000, reason: 'you fronted r1 and lose the credit');

      // Everyone it touches is reported, biggest movement first.
      expect(shifts.map((s) => s.person), containsAll(['you', 'a', 'b']));
      expect(shifts.first.person, 'you');
    });

    test('says nothing about people it does not touch', () {
      final g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          bill(id: 'r1', paidBy: 'you', amount: 30, party: const ['you', 'a']),
          bill(id: 'r2', paidBy: 'b', amount: 30, party: const ['b', 'c']),
        ],
      );
      final shifts = shiftIfDeleted(g, 'r1');
      expect(shifts.map((s) => s.person), unorderedEquals(['you', 'a']));
    });

    test('asking does not change anything', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          bill(id: 'r1', paidBy: 'you', amount: 30, party: const ['you', 'a']),
        ],
      );
      g = g.copyWith(
        settlements: const [Settlement(from: 'a', to: 'you', cents: 1500)],
      );
      final before = g.settlements.length;
      shiftIfDeleted(g, 'r1');
      overpaymentIfDeleted(g, 'r1');
      expect(g.receipts, hasLength(1));
      expect(g.settlements, hasLength(before));
    });
  });

  group('refunds are marked as refunds', () {
    test('a refund is flagged and a payment is not', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          bill(id: 'r1', paidBy: 'you', amount: 30, party: const ['you', 'a']),
        ],
      );
      g = g.copyWith(
        settlements: const [Settlement(from: 'a', to: 'you', cents: 1500)],
      );
      final after = withOverpaymentsRefunded(g.copyWith(receipts: const []));

      expect(after.settlements.first.refund, isFalse);
      expect(after.settlements.last.refund, isTrue);
    });

    test('a refund is never itself reversed', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          bill(id: 'r1', paidBy: 'you', amount: 30, party: const ['you', 'a']),
        ],
      );
      g = g.copyWith(
        settlements: const [Settlement(from: 'a', to: 'you', cents: 1500)],
      );
      final after = withOverpaymentsRefunded(g.copyWith(receipts: const []));

      // 'you' handed money back, which must not now look like a payment of
      // theirs waiting to be undone.
      expect(refundsFor(after, 'you'), isEmpty);
      expect(overpaidBy(after), isEmpty);
    });

    test('a second deletion does not reverse the same payment twice', () {
      // The multi-deletion bug. Ana pays two people; two bills are then
      // deleted one after the other. Each pass used to walk Ana's payments
      // from the newest with no memory of the last, so the newest payment was
      // reversed twice over and one person handed back more than they were
      // ever given.
      const party = ['you', 'a', 'b'];
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          bill(id: 'r1', paidBy: 'you', amount: 30, party: party),
          bill(id: 'r2', paidBy: 'b', amount: 60, party: party),
        ],
      );
      g = g.copyWith(
        settlements: const [
          Settlement(from: 'a', to: 'b', cents: 2000),
          Settlement(from: 'a', to: 'you', cents: 1000),
        ],
      );

      g = withOverpaymentsRefunded(
        g.copyWith(receipts: g.receipts.where((r) => r.id != 'r1').toList()),
      );
      g = withOverpaymentsRefunded(
        g.copyWith(receipts: g.receipts.where((r) => r.id != 'r2').toList()),
      );

      // Nobody may hand back more than they were given.
      for (final person in party) {
        final got = g.settlements
            .where((s) => !s.refund && s.to == person)
            .fold(0, (a, s) => a + s.cents);
        final gave = g.settlements
            .where((s) => s.refund && s.from == person)
            .fold(0, (a, s) => a + s.cents);
        expect(
          gave,
          lessThanOrEqualTo(got),
          reason: '$person handed back more than they ever received',
        );
      }

      expect(overpaidBy(g), isEmpty);
      expect(aggregate(g, (id) => id).allSquare, isTrue);
    });

    test('the money is asked back from whoever is holding it', () {
      // You paid Ben for the taxi on Monday and Cara for dinner on Tuesday.
      // The taxi is deleted, so it is Ben holding money for nothing - but
      // reversing the most recent payment picks Cara, who is square, and
      // leaves Ben with the taxi money.
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          Receipt(
            id: 'taxi',
            name: 'Taxi',
            date: '1 Jan',
            paidBy: 'b',
            party: const ['you', 'b'],
            lines: [item('l1', 'Taxi', 10)],
            assign: const {
              'l1': ['you'],
            },
          ),
          Receipt(
            id: 'dinner',
            name: 'Dinner',
            date: '2 Jan',
            paidBy: 'c',
            party: const ['you', 'c'],
            lines: [item('l1', 'Dinner', 10)],
            assign: const {
              'l1': ['you'],
            },
          ),
        ],
      );
      g = g.copyWith(
        settlements: const [
          Settlement(from: 'you', to: 'b', cents: 1000),
          Settlement(from: 'you', to: 'c', cents: 1000),
        ],
      );
      expect(aggregate(g, (id) => id).allSquare, isTrue);

      final after = withOverpaymentsRefundedFor(
        g.copyWith(receipts: g.receipts.where((r) => r.id != 'taxi').toList()),
        {'you'},
      );

      final back = after.settlements.where((s) => s.refund).toList();
      expect(back, hasLength(1));
      expect(back.single.from, 'b',
          reason: 'Ben is the one holding money for a taxi that is gone');
      expect(back.single.to, 'you');
      expect(aggregate(after, (id) => id).allSquare, isTrue);
    });

    test('deleting one bill does not sweep up an overpayment left standing', () {
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          bill(id: 'r1', paidBy: 'you', amount: 30, party: const ['you', 'a']),
          bill(id: 'r2', paidBy: 'you', amount: 30, party: const ['you', 'b']),
        ],
      );
      g = g.copyWith(
        settlements: const [
          Settlement(from: 'a', to: 'you', cents: 1500),
          Settlement(from: 'b', to: 'you', cents: 1500),
        ],
      );

      // Delete the first and decline the refund: Ana is left holding €15.
      g = g.copyWith(receipts: g.receipts.where((r) => r.id != 'r1').toList());
      expect(overpaidBy(g), {'a': 1500});

      // Now delete the second and take the refund. It must hand back Ben's
      // €15 and leave Ana's decision alone.
      final caused = overpaymentIfDeleted(g, 'r2').keys.toSet();
      final after = withOverpaymentsRefundedFor(
        g.copyWith(receipts: g.receipts.where((r) => r.id != 'r2').toList()),
        caused,
      );

      final back = after.settlements.where((s) => s.refund).toList();
      expect(back.fold(0, (t, s) => t + s.cents), 1500,
          reason: 'the button named €15, so €15 is what may move');
      expect(back.single.to, 'b');
      expect(overpaidBy(after), {'a': 1500},
          reason: "Ana's standing credit was not the user's choice to undo");
    });

    test('the flag survives a round trip, and old stores still load', () {
      const s = Settlement(from: 'a', to: 'b', cents: 100, refund: true);
      expect(Settlement.fromJson(s.toJson()).refund, isTrue);

      // Written before the flag existed.
      expect(
        Settlement.fromJson(const {
          'from': 'a',
          'to': 'b',
          'cents': 100,
        }).refund,
        isFalse,
      );
    });
  });

  test('fuzzing: deleting bill after bill keeps the books straight', () {
    final rng = Random(20260915);

    for (var round = 0; round < 200; round++) {
      final people = ['you', 'a', 'b', 'c'].take(2 + rng.nextInt(3)).toList();
      var g = Group(
        id: 'g',
        name: 'Trip',
        receipts: [
          for (var i = 0; i < 2 + rng.nextInt(4); i++)
            bill(
              id: 'r$i',
              paidBy: people[rng.nextInt(people.length)],
              amount: (1 + rng.nextInt(9000)) / 100,
              party: people,
            ),
        ],
      );

      // Settle up, then delete the bills one at a time, refunding as we go.
      for (final t in aggregate(g, (id) => id).transfers) {
        g = g.copyWith(
          settlements: [
            ...g.settlements,
            Settlement(from: t.from, to: t.to, cents: t.cents),
          ],
        );
      }

      final ids = g.receipts.map((r) => r.id).toList()..shuffle(rng);
      var ledger = g.settlements.length;

      for (final id in ids) {
        // The preview must agree with what actually happens.
        final promised = {
          for (final s in shiftIfDeleted(g, id)) s.person: s.after,
        };

        g = g.copyWith(
          receipts: g.receipts.where((r) => r.id != id).toList(),
        );
        final actual = {
          for (final p in aggregate(g, (id) => id).people) p.friendId: p.netCents,
        };
        promised.forEach((person, net) {
          expect(
            actual[person] ?? 0,
            net,
            reason: 'round $round: the warning promised the wrong figure',
          );
        });

        g = withOverpaymentsRefunded(g);

        expect(overpaidBy(g), isEmpty, reason: 'round $round after $id');
        final t = aggregate(g, (id) => id);
        expect(t.people.fold(0, (s, p) => s + p.netCents), 0);
        expect(g.settlements.length, greaterThanOrEqualTo(ledger));
        ledger = g.settlements.length;
      }

      // Every bill gone and every debt handed back: nobody owes anybody.
      expect(g.receipts, isEmpty);
      expect(
        aggregate(g, (id) => id).allSquare,
        isTrue,
        reason: 'round $round: the group did not end square',
      );
    }
  });

  test('fuzzing: refunding always terminates and always squares up', () {
    final rng = Random(20260915);

    for (var round = 0; round < 300; round++) {
      final people = ['you', 'a', 'b', 'c'].take(2 + rng.nextInt(3)).toList();
      final receipts = <Receipt>[
        for (var i = 0; i < 1 + rng.nextInt(4); i++)
          bill(
            id: 'r$i',
            paidBy: people[rng.nextInt(people.length)],
            amount: (1 + rng.nextInt(9000)) / 100,
            party: people,
          ),
      ];
      var g = Group(id: 'g', name: 'Trip', receipts: receipts);

      // Settle some of the suggested transfers, in whole or in part.
      for (final t in aggregate(g, (id) => id).transfers) {
        if (rng.nextBool()) continue;
        final part = rng.nextBool() ? t.cents : 1 + rng.nextInt(t.cents);
        g = g.copyWith(
          settlements: [
            ...g.settlements,
            Settlement(from: t.from, to: t.to, cents: part),
          ],
        );
      }

      // Then throw bills away.
      final keep = g.receipts.where((_) => rng.nextBool()).toList();
      final after = withOverpaymentsRefunded(g.copyWith(receipts: keep));

      expect(
        overpaidBy(after),
        isEmpty,
        reason: 'round $round left somebody holding money',
      );

      // The books still balance, and no payment was ever edited away.
      final t = aggregate(after, (id) => id);
      expect(t.people.fold(0, (s, p) => s + p.netCents), 0);
      expect(
        after.settlements.length,
        greaterThanOrEqualTo(g.settlements.length),
        reason: 'the ledger must only ever grow',
      );
      for (var i = 0; i < g.settlements.length; i++) {
        expect(after.settlements[i].cents, g.settlements[i].cents);
        expect(after.settlements[i].from, g.settlements[i].from);
      }
    }
  });
}
