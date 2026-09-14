import 'dart:math';

import 'package:bill/logic/aggregate.dart';
import 'package:bill/logic/receipt_payments.dart';
import 'package:bill/logic/settle_up.dart';
import 'package:bill/logic/shares.dart';
import 'package:bill/model/models.dart';
import 'package:bill/model/money.dart';
import 'package:bill/parsing/receipt.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------- helpers

ReceiptLine line(String id, String desc, double amount,
        {LineKind kind = LineKind.item}) =>
    ReceiptLine(
        id: id,
        description: desc,
        amount: amount,
        kind: kind,
        rawText: desc);

Receipt bill({
  required String id,
  required String paidBy,
  required List<String> party,
  required List<ReceiptLine> lines,
  required Map<String, List<String>> assign,
  String? name,
}) =>
    Receipt(
      id: id,
      name: name ?? 'Bill $id',
      date: '1 Jan',
      paidBy: paidBy,
      party: party,
      lines: lines,
      assign: assign,
    );

AppState stateWith(List<Receipt> receipts, {List<Settlement> paid = const []}) {
  final app = AppState.ephemeral();
  app.friends = const [
    Friend(id: 'you', name: 'You', color: 1),
    Friend(id: 'a', name: 'Ana', color: 2),
    Friend(id: 'b', name: 'Ben', color: 3),
    Friend(id: 'c', name: 'Cat', color: 4),
  ];
  app.groups = [
    Group(id: 'g', name: 'Trip', receipts: receipts, settlements: paid)
  ];
  return app;
}

Map<String, int> nets(AppState app) {
  final t = app.totalsFor(app.groupById('g')!);
  return {for (final p in t.people) p.friendId: p.netCents};
}

GroupTotals totals(AppState app) => app.totalsFor(app.groupById('g')!);

/// Every invariant the group books have to satisfy, at any moment.
void checkBooks(AppState app, String where) {
  final t = totals(app);

  expect(t.people.fold(0, (s, p) => s + p.netCents), 0,
      reason: '$where: the nets must sum to zero');

  final after = {for (final p in t.people) p.friendId: p.netCents};
  for (final x in t.transfers) {
    expect(x.cents, greaterThan(0), reason: '$where: an empty transfer');
    expect(x.from, isNot(x.to), reason: '$where: a transfer to oneself');
    after[x.from] = (after[x.from] ?? 0) - x.cents;
    after[x.to] = (after[x.to] ?? 0) + x.cents;
  }
  expect(after.values.every((v) => v == 0), isTrue,
      reason: '$where: the suggested payments do not clear the debts');

  final owed = t.people.fold(0, (s, p) => s + (p.netCents > 0 ? p.netCents : 0));
  expect(t.outstandingCents, owed,
      reason: '$where: outstanding must be what is still owed');
  expect(t.outstandingCents == 0, t.transfers.isEmpty,
      reason: '$where: nothing outstanding means nothing to pay, and '
          'vice versa');
}

void payEverything(AppState app) {
  var guard = 0;
  while (totals(app).transfers.isNotEmpty && guard++ < 30) {
    final x = totals(app).transfers.first;
    app.recordSettlement('g', x.from, x.to, x.cents);
  }
  expect(guard, lessThan(30), reason: 'settling never finished');
}

// ------------------------------------------------------------------ tests

void main() {
  group('the shape of a group', () {
    test('a bill the payer covered alone owes nobody anything', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you'],
            lines: [line('l', 'Coffee', 8.90)],
            assign: const {
              'l': ['you']
            }),
      ]);
      checkBooks(app, 'solo bill');
      expect(nets(app)['you'], 0);
      expect(totals(app).outstandingCents, 0);
      expect(totals(app).spentCents, 890);
    });

    test('one debtor, one creditor', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a'],
            lines: [line('l', 'Meal', 20)],
            assign: const {
              'l': ['you', 'a']
            }),
      ]);
      checkBooks(app, 'two people');
      expect(nets(app), {'you': -1000, 'a': 1000});
      expect(totals(app).outstandingCents, 1000);
    });

    test('debts between two people cancel without anyone paying', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a'],
            lines: [line('l', 'Dinner', 20)],
            assign: const {
              'l': ['you', 'a']
            }),
        bill(
            id: 'r2',
            paidBy: 'a',
            party: const ['you', 'a'],
            lines: [line('l', 'Taxi', 20)],
            assign: const {
              'l': ['you', 'a']
            }),
      ]);
      checkBooks(app, 'mutual debts');
      expect(nets(app), {'you': 0, 'a': 0});
      expect(totals(app).transfers, isEmpty);
      expect(totals(app).spentCents, 4000,
          reason: 'forty was still spent, even though nobody owes anything');
    });

    test('money nobody has claimed belongs to nobody', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a'],
            lines: [line('l1', 'Wine', 20), line('l2', 'Bread', 6)],
            assign: const {
              'l1': ['you', 'a']
            }),
      ]);
      checkBooks(app, 'unassigned');
      expect(nets(app), {'you': -1000, 'a': 1000});
      expect(totals(app).spentCents, 2600);
      expect(totals(app).unassigned.single.$2, 600);
    });

    test('a discount can leave somebody owed money on a bill', () {
      final app = stateWith([
        bill(
          id: 'r1',
          paidBy: 'you',
          party: const ['you', 'a'],
          lines: [
            line('l1', 'Meal', 20),
            line('d1', 'Voucher', 30, kind: LineKind.discount),
          ],
          assign: const {
            'l1': ['a'],
            'd1': ['a'],
          },
        ),
      ]);
      checkBooks(app, 'a discount bigger than the item');
      // Ana's share is 20 - 30 = -10, so she is owed ten.
      expect(nets(app)['a'], -1000);
      expect(nets(app)['you'], 1000);
    });

    test('somebody dropped from the party does not take their share away', () {
      final app = stateWith([
        bill(
          id: 'r1',
          paidBy: 'you',
          party: const ['you', 'a'],
          lines: [line('l', 'Platter', 12)],
          assign: const {
            'l': ['you', 'a', 'gone']
          },
        ),
      ]);
      checkBooks(app, 'a departed friend');
      expect(nets(app), {'you': -600, 'a': 600});
    });
  });

  group('recording payments', () {
    test('paying what is suggested clears exactly that much', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a', 'b'],
            lines: [line('l', 'Dinner', 30)],
            assign: const {
              'l': ['you', 'a', 'b']
            }),
      ]);
      checkBooks(app, 'before');

      app.recordSettlement('g', 'a', 'you', 1000);
      checkBooks(app, 'after one payment');
      expect(nets(app), {'you': -1000, 'a': 0, 'b': 1000});
    });

    test('a second payment does not re-count the first', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a', 'b'],
            lines: [line('l', 'Dinner', 30)],
            assign: const {
              'l': ['you', 'a', 'b']
            }),
      ]);

      app.recordSettlement('g', 'a', 'you', 1000);
      final afterFirst = nets(app);
      app.recordSettlement('g', 'b', 'you', 1000);

      checkBooks(app, 'after two payments');
      expect(afterFirst['a'], 0);
      expect(nets(app), {'you': 0, 'a': 0, 'b': 0},
          reason: 'the first payment must still count, and only once');
      expect(totals(app).outstandingCents, 0);
    });

    test('a part payment leaves the remainder', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a'],
            lines: [line('l', 'Dinner', 20)],
            assign: const {
              'l': ['you', 'a']
            }),
      ]);
      app.recordSettlement('g', 'a', 'you', 400);
      checkBooks(app, 'part payment');
      expect(nets(app), {'you': -600, 'a': 600});
      expect(totals(app).transfers.single.cents, 600);
    });

    test('paying more than owed leaves the payer owed the difference', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a'],
            lines: [line('l', 'Dinner', 20)],
            assign: const {
              'l': ['you', 'a']
            }),
      ]);
      app.recordSettlement('g', 'a', 'you', 1500);
      checkBooks(app, 'overpayment');
      expect(nets(app), {'you': 500, 'a': -500},
          reason: 'Ana paid five hundred too much and is owed it back');
      expect(totals(app).transfers.single.from, 'you');
    });

    test('a payment between two people leaves everyone else alone', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a', 'b', 'c'],
            lines: [line('l', 'Dinner', 40)],
            assign: const {
              'l': ['you', 'a', 'b', 'c']
            }),
      ]);
      final before = nets(app);
      app.recordSettlement('g', 'a', 'you', 1000);
      final after = nets(app);

      expect(after['b'], before['b']);
      expect(after['c'], before['c']);
      checkBooks(app, 'third parties');
    });

    test('a payment nobody owed still balances', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a'],
            lines: [line('l', 'Dinner', 20)],
            assign: const {
              'l': ['you', 'a']
            }),
      ]);
      // Ben pays Cat for no reason the app knows about.
      app.recordSettlement('g', 'b', 'c', 500);
      checkBooks(app, 'an unexplained payment');
      expect(nets(app)['b'], -500);
      expect(nets(app)['c'], 500);
    });

    test('an empty or negative payment is refused', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a'],
            lines: [line('l', 'Dinner', 20)],
            assign: const {
              'l': ['you', 'a']
            }),
      ]);
      app.recordSettlement('g', 'a', 'you', 0);
      app.recordSettlement('g', 'a', 'you', -500);
      expect(app.groupById('g')!.settlements, isEmpty);
      checkBooks(app, 'nonsense payments');
    });

    test('paying everything suggested leaves everybody square', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a', 'b'],
            lines: [line('l', 'Dinner', 31)],
            assign: const {
              'l': ['you', 'a', 'b']
            }),
        bill(
            id: 'r2',
            paidBy: 'a',
            party: const ['you', 'a', 'b'],
            lines: [line('l', 'Taxi', 17)],
            assign: const {
              'l': ['you', 'a', 'b']
            }),
        bill(
            id: 'r3',
            paidBy: 'b',
            party: const ['a', 'b'],
            lines: [line('l', 'Museum', 9)],
            assign: const {
              'l': ['a', 'b']
            }),
      ]);
      payEverything(app);
      checkBooks(app, 'fully settled');
      expect(totals(app).outstandingCents, 0);
      expect(nets(app).values.every((v) => v == 0), isTrue);
    });
  });

  group('the group changing after payments', () {
    test('a new bill only adds what the new bill costs', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a', 'b'],
            lines: [line('l', 'Dinner', 30)],
            assign: const {
              'l': ['you', 'a', 'b']
            }),
      ]);
      payEverything(app);
      expect(nets(app).values.every((v) => v == 0), isTrue);

      final g = app.groupById('g')!;
      app.groups = [
        g.copyWith(receipts: [
          ...g.receipts,
          bill(
              id: 'r2',
              paidBy: 'a',
              party: const ['you', 'a', 'b'],
              lines: [line('l', 'Taxi', 30)],
              assign: const {
                'l': ['you', 'a', 'b']
              }),
        ])
      ];

      checkBooks(app, 'after a new bill');
      expect(nets(app), {'you': 1000, 'a': -2000, 'b': 1000},
          reason: 'the settled dinner must not come back into it');
      expect(totals(app).outstandingCents, 2000);
    });

    test('editing a paid bill reopens only the difference', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a'],
            lines: [line('l', 'Dinner', 20)],
            assign: const {
              'l': ['you', 'a']
            }),
      ]);
      payEverything(app);

      final g = app.groupById('g')!;
      app.groups = [
        g.copyWith(receipts: [
          g.receipts.single.copyWith(lines: [line('l', 'Dinner', 30)]),
        ])
      ];

      checkBooks(app, 'after an edit');
      expect(totals(app).transfers.single.cents, 500,
          reason: 'the bill grew by ten, so five more is owed');
    });

    test('deleting a paid bill leaves the payment standing', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a'],
            lines: [line('l', 'Dinner', 20)],
            assign: const {
              'l': ['you', 'a']
            }),
      ]);
      payEverything(app);
      app.deleteReceipt('g', 'r1');

      checkBooks(app, 'after deleting');
      expect(nets(app)['a'], -1000,
          reason: 'Ana paid for a bill that no longer exists, so she is owed '
              'it back rather than the payment vanishing');
    });

    test('undoing a payment puts the debt back exactly', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a'],
            lines: [line('l', 'Dinner', 20)],
            assign: const {
              'l': ['you', 'a']
            }),
      ]);
      final before = nets(app);
      app.recordSettlement('g', 'a', 'you', 1000);
      app.undoSettlementRecord(
          'g', app.groupById('g')!.settlements.single);

      checkBooks(app, 'after undo');
      expect(nets(app), before);
    });
  });

  group('rounding', () {
    test('a tenner three ways loses nothing', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a', 'b'],
            lines: [line('l', 'Meal', 10)],
            assign: const {
              'l': ['you', 'a', 'b']
            }),
      ]);
      checkBooks(app, 'ten three ways');
      expect(nets(app)['a']! + nets(app)['b']!, -nets(app)['you']!);
    });

    test('a penny three ways', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a', 'b'],
            lines: [line('l', 'Sweet', 0.01)],
            assign: const {
              'l': ['you', 'a', 'b']
            }),
      ]);
      checkBooks(app, 'one penny three ways');
      expect(computeShares(app.groupById('g')!.receipts.single).per.values
          .fold(0, (s, v) => s + v), 1);
    });

    test('awkward amounts across many people still balance', () {
      for (final amount in [0.03, 0.07, 9.99, 33.33, 100.01, 1234.56]) {
        for (final n in [2, 3, 4]) {
          final party = ['you', 'a', 'b', 'c'].take(n).toList();
          final app = stateWith([
            bill(
                id: 'r1',
                paidBy: 'you',
                party: party,
                lines: [line('l', 'Thing', amount)],
                assign: {'l': party}),
          ]);
          checkBooks(app, '$amount between $n');
          expect(
            computeShares(app.groupById('g')!.receipts.single)
                .per
                .values
                .fold(0, (s, v) => s + v),
            toCents(amount),
          );
        }
      }
    });
  });

  group('what each bill has had paid towards it', () {
    test('paying everything marks every bill paid', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a', 'b'],
            lines: [line('l', 'Dinner', 30)],
            assign: const {
              'l': ['you', 'a', 'b']
            }),
        bill(
            id: 'r2',
            paidBy: 'a',
            party: const ['you', 'a', 'b'],
            lines: [line('l', 'Taxi', 15)],
            assign: const {
              'l': ['you', 'a', 'b']
            }),
      ]);
      payEverything(app);

      final payments = receiptPayments(app.groupById('g')!);
      for (final r in app.groupById('g')!.receipts) {
        expect(payments[r.id]!.progress, PaymentProgress.full,
            reason: '${r.id} should read as paid once everyone is square');
      }
    });

    test('a bill nobody has paid towards shows nothing', () {
      final app = stateWith([
        bill(
            id: 'r1',
            paidBy: 'you',
            party: const ['you', 'a', 'b'],
            lines: [line('l', 'Dinner', 30)],
            assign: const {
              'l': ['you', 'a', 'b']
            }),
      ]);
      expect(receiptPayments(app.groupById('g')!)['r1']!.progress,
          PaymentProgress.none);
    });
  });

  group('fuzzing', () {
    Group randomGroup(Random r) {
      final everybody = ['you', 'a', 'b', 'c'];
      final receipts = <Receipt>[];
      for (var i = 0; i < 1 + r.nextInt(5); i++) {
        final present = ([...everybody]..shuffle(r))
            .take(2 + r.nextInt(3))
            .toList();
        final lines = <ReceiptLine>[];
        final assign = <String, List<String>>{};
        for (var j = 0; j < 1 + r.nextInt(3); j++) {
          final amount = (r.nextInt(8000) + 1) / 100;
          final kind = r.nextInt(7) == 0 ? LineKind.discount : LineKind.item;
          lines.add(line('l$j', 'Thing $j', amount, kind: kind));
          final sharers = ([...present]..shuffle(r))
              .take(r.nextInt(present.length + 1))
              .toList();
          assign['l$j'] = sharers;
        }
        receipts.add(bill(
          id: 'r$i',
          paidBy: present[r.nextInt(present.length)],
          party: present,
          lines: lines,
          assign: assign,
        ));
      }
      return Group(id: 'g', name: 'Trip', receipts: receipts);
    }

    test('the books hold for six hundred random groups, settled step by step',
        () {
      for (var seed = 0; seed < 600; seed++) {
        final r = Random(seed);
        final app = AppState.ephemeral();
        app.friends = const [
          Friend(id: 'you', name: 'You', color: 1),
          Friend(id: 'a', name: 'Ana', color: 2),
          Friend(id: 'b', name: 'Ben', color: 3),
          Friend(id: 'c', name: 'Cat', color: 4),
        ];
        app.groups = [randomGroup(r)];

        var guard = 0;
        while (guard++ < 30) {
          checkBooks(app, 'seed $seed step $guard');
          final t = totals(app);
          if (t.transfers.isEmpty) break;

          final x = t.transfers[r.nextInt(t.transfers.length)];
          final owedBefore = t.outstandingCents;
          app.recordSettlement('g', x.from, x.to, x.cents);

          expect(totals(app).outstandingCents, owedBefore - x.cents,
              reason: 'seed $seed: paying ${x.cents} should reduce what is '
                  'outstanding by exactly that');
        }
        expect(guard, lessThan(30), reason: 'seed $seed never settled');
      }
    });

    test('settle-up is minimal and exact for random positions', () {
      for (var seed = 0; seed < 3000; seed++) {
        final r = Random(seed);
        final n = 2 + r.nextInt(5);
        final position = <String, int>{};
        var running = 0;
        for (var i = 0; i < n - 1; i++) {
          final v = r.nextInt(20001) - 10000;
          position['p$i'] = v;
          running += v;
        }
        position['p${n - 1}'] = -running;

        final list = settleUp(position);
        final after = {...position};
        for (final t in list) {
          after[t.from] = after[t.from]! - t.cents;
          after[t.to] = after[t.to]! + t.cents;
        }
        expect(after.values.every((v) => v == 0), isTrue, reason: 'seed $seed');

        final debtors = position.values.where((v) => v > 0).length;
        final creditors = position.values.where((v) => v < 0).length;
        if (debtors + creditors > 0) {
          expect(list.length, lessThanOrEqualTo(debtors + creditors - 1),
              reason: 'seed $seed: more payments than necessary');
        }
      }
    });
  });
}
