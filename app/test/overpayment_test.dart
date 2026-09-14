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
