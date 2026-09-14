import 'package:bill/logic/aggregate.dart';
import 'package:bill/logic/settle_up.dart';
import 'package:bill/logic/shares.dart';
import 'package:bill/model/models.dart';
import 'package:bill/model/money.dart';
import 'package:bill/parsing/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptLine line(String id, String desc, double amt,
        {LineKind kind = LineKind.item}) =>
    ReceiptLine(
      id: id,
      description: desc,
      amount: amt,
      kind: kind,
      rawText: '$desc $amt',
    );

Receipt receipt({
  String id = 'r',
  String paidBy = 'you',
  required List<ReceiptLine> lines,
  required Map<String, List<String>> assign,
  required List<String> party,
}) =>
    Receipt(
      id: id,
      name: 'Bill $id',
      date: '14 Sep',
      paidBy: paidBy,
      lines: lines,
      assign: assign,
      party: party,
    );

void main() {
  group('allocate', () {
    test('splits evenly when it divides', () {
      expect(allocate(1000, 4), [250, 250, 250, 250]);
    });

    test('leftover pennies are handed out one each and nothing is lost', () {
      final parts = allocate(1000, 3);
      expect(parts, [334, 333, 333]);
      expect(parts.reduce((a, b) => a + b), 1000);
    });

    test('negative amounts allocate by magnitude then flip', () {
      final parts = allocate(-1000, 3);
      expect(parts, [-334, -333, -333]);
      expect(parts.reduce((a, b) => a + b), -1000);
    });

    test('never loses or invents a penny, for any total and any party size',
        () {
      for (var total = -500; total <= 500; total++) {
        for (var n = 1; n <= 8; n++) {
          final parts = allocate(total, n);
          expect(parts.length, n);
          expect(parts.reduce((a, b) => a + b), total,
              reason: 'total=$total n=$n');
        }
      }
    });
  });

  group('shares', () {
    test('a tenner three ways still adds up to a tenner', () {
      final r = receipt(
        lines: [line('i1', 'Platter', 10.00)],
        assign: {
          'i1': ['you', 'a', 'b']
        },
        party: ['you', 'a', 'b'],
      );
      final s = computeShares(r);
      expect(s.per.values.reduce((a, b) => a + b), 1000);
      expect(s.distributedCents, s.grandCents);
    });

    test('unassigned rows go to nobody but still count towards the total', () {
      final r = receipt(
        lines: [line('i1', 'Wine', 20.00), line('i2', 'Bread', 4.00)],
        assign: {
          'i1': ['you']
        },
        party: ['you', 'a'],
      );
      final s = computeShares(r);
      expect(s.per['you'], 2000);
      expect(s.per['a'], 0);
      expect(s.grandCents, 2400);
      expect(s.distributedCents, 2000);
      expect(s.unassignedCents, 400);
    });

    test('a discount reduces the people who share it', () {
      final r = receipt(
        lines: [
          line('i1', 'Meal', 20.00),
          line('d1', 'Voucher', 5.00, kind: LineKind.discount),
        ],
        assign: {
          'i1': ['you', 'a'],
          'd1': ['you', 'a'],
        },
        party: ['you', 'a'],
      );
      final s = computeShares(r);
      expect(s.per['you'], 750);
      expect(s.per['a'], 750);
      expect(s.grandCents, 1500);
    });

    test('someone dropped from the party does not take their share with them',
        () {
      // Assigned to three, but only two are still in the party.
      final r = receipt(
        lines: [line('i1', 'Platter', 12.00)],
        assign: {
          'i1': ['you', 'a', 'gone']
        },
        party: ['you', 'a'],
      );
      final s = computeShares(r);
      expect(s.per['you'], 600);
      expect(s.per['a'], 600);
      expect(s.distributedCents, s.grandCents,
          reason: 'the row must still be fully distributed');
    });
  });

  group('settle up', () {
    test('two people, one payment', () {
      final t = settleUp({'you': -2000, 'a': 2000});
      expect(t.length, 1);
      expect(t.single.from, 'a');
      expect(t.single.to, 'you');
      expect(t.single.cents, 2000);
    });

    test('transfers exactly clear every debt', () {
      final nets = {'you': -3000, 'a': 1000, 'b': 1500, 'c': 500};
      final t = settleUp(nets);
      final after = {...nets};
      for (final x in t) {
        after[x.from] = after[x.from]! - x.cents;
        after[x.to] = after[x.to]! + x.cents;
      }
      expect(after.values.every((v) => v == 0), isTrue);
      expect(t.length, lessThanOrEqualTo(3));
    });

    test('nobody owing anything produces no payments', () {
      expect(settleUp({'you': 0, 'a': 0}), isEmpty);
    });
  });

  group('group aggregation', () {
    String nameOf(String id) => id;

    test('nets always sum to zero, even with rows unassigned', () {
      final g = Group(id: 'g', name: 'Trip', receipts: [
        receipt(
          id: 'r1',
          paidBy: 'you',
          lines: [line('i1', 'Wine', 30.00), line('i2', 'Olives', 9.00)],
          assign: {
            'i1': ['you', 'a', 'b']
          }, // olives unclaimed
          party: ['you', 'a', 'b'],
        ),
      ]);
      final t = aggregate(g, nameOf);
      expect(t.people.fold(0, (s, p) => s + p.netCents), 0);
    });

    test('the payer is credited with the distributed total, not the face total',
        () {
      final g = Group(id: 'g', name: 'Trip', receipts: [
        receipt(
          id: 'r1',
          paidBy: 'you',
          lines: [line('i1', 'Wine', 30.00), line('i2', 'Olives', 9.00)],
          assign: {
            'i1': ['you', 'a', 'b']
          },
          party: ['you', 'a', 'b'],
        ),
      ]);
      final t = aggregate(g, nameOf);
      final you = t.people.firstWhere((p) => p.friendId == 'you');
      // Credited 30.00 distributed, not the 39.00 face total.
      expect(you.paidCents, 3000);
      expect(you.shareCents, 1000);
      expect(you.netCents, -2000);
      // The hero total still shows the full 39.00 that was spent.
      expect(t.spentCents, 3900);
      expect(t.unassigned.single.$2, 900);
    });

    test('marking a debt paid clears it and keeps the invariant', () {
      var g = Group(id: 'g', name: 'Trip', receipts: [
        receipt(
          id: 'r1',
          paidBy: 'you',
          lines: [line('i1', 'Dinner', 30.00)],
          assign: {
            'i1': ['you', 'a', 'b']
          },
          party: ['you', 'a', 'b'],
        ),
      ]);
      final before = aggregate(g, nameOf);
      expect(before.transfers.length, 2);

      for (final x in before.transfers) {
        g = g.copyWith(settlements: [
          ...g.settlements,
          Settlement(from: x.from, to: x.to, cents: x.cents),
        ]);
      }

      final after = aggregate(g, nameOf);
      expect(after.transfers, isEmpty);
      expect(after.allSquare, isTrue);
      expect(after.people.fold(0, (s, p) => s + p.netCents), 0);
    });

    test('what the group spent is every receipt it holds', () {
      final g = Group(id: 'g', name: 'Trip', receipts: [
        receipt(
          id: 'r1',
          paidBy: 'you',
          lines: [line('i1', 'Dinner', 30.00)],
          assign: {
            'i1': ['you', 'a']
          },
          party: ['you', 'a'],
        ),
        receipt(
          id: 'r2',
          paidBy: 'a',
          lines: [line('i1', 'Taxi', 10.00)],
          assign: {
            'i1': ['you', 'a']
          },
          party: ['you', 'a'],
        ),
      ]);
      final t = aggregate(g, nameOf);
      expect(t.spentCents, 4000);
      // You paid 30 and owe 20; Ana paid 10 and owes 20.
      expect(t.people.firstWhere((p) => p.friendId == 'you').netCents, -1000);
      expect(t.outstandingCents, 1000);
    });

    test('a settlement recorded before a bill changed leaves a residual', () {
      // LOGIC.md section 8: settlements are frozen. If the bill grows
      // afterwards, the difference must reappear as a new transfer.
      var g = Group(id: 'g', name: 'Trip', receipts: [
        receipt(
          id: 'r1',
          paidBy: 'you',
          lines: [line('i1', 'Dinner', 20.00)],
          assign: {
            'i1': ['you', 'a']
          },
          party: ['you', 'a'],
        ),
      ]);
      g = g.copyWith(
          settlements: [const Settlement(from: 'a', to: 'you', cents: 1000)]);
      expect(aggregate(g, nameOf).transfers, isEmpty);

      // The bill is re-read: dinner was actually 30.00.
      g = g.copyWith(receipts: [
        g.receipts.single.copyWith(lines: [line('i1', 'Dinner', 30.00)]),
      ]);
      final after = aggregate(g, nameOf);
      expect(after.transfers.single.from, 'a');
      expect(after.transfers.single.cents, 500);
    });
  });

  group('balance banner', () {
    test('hidden entirely when no printed figure was read', () {
      final r = receipt(
        lines: [line('i1', 'Coffee', 3.00)],
        assign: const {},
        party: const ['you'],
      );
      expect(checkBalance(r).hasTarget, isFalse);
    });

    test('checks items against the printed subtotal, ignoring extras', () {
      final r = Receipt(
        id: 'r',
        name: 'Dinner',
        date: '14 Sep',
        paidBy: 'you',
        party: const ['you'],
        assign: const {},
        printedSubtotal: 47.00,
        printedTotal: 51.70,
        lines: [
          line('i1', 'Burrata', 8.00),
          line('i2', 'Margherita', 9.50),
          line('i3', 'Diavola', 11.00),
          line('i4', 'Peroni', 9.00),
          line('i5', 'Tiramisu', 6.50),
          line('i6', 'Water', 3.00),
          line('a1', 'Service 10%', 4.70, kind: LineKind.adjustment),
        ],
      );
      final b = checkBalance(r);
      expect(b.hasTarget, isTrue);
      expect(b.itemSum, closeTo(47.00, 0.001));
      expect(b.balanced, isTrue);
    });
  });

  group('formatting', () {
    test('minus sign leads, symbol hugs the number', () {
      expect(formatMoney(40, '€'), '€40.00');
      expect(formatMoney(-40, '€'), '−€40.00');
      expect(formatMoney(0, '£'), '£0.00');
    });
  });
}
