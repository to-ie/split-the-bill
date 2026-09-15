import 'package:bill/logic/aggregate.dart';
import 'package:bill/logic/receipt_payments.dart';
import 'package:bill/model/models.dart';
import 'package:bill/parsing/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptLine line(String id, String desc, double amount) => ReceiptLine(
      id: id,
      description: desc,
      amount: amount,
      kind: LineKind.item,
      rawText: desc,
    );

Receipt dinner({
  required String id,
  required String paidBy,
  required double amount,
  required List<String> party,
}) =>
    Receipt(
      id: id,
      name: 'Bill $id',
      date: '1 Jan',
      paidBy: paidBy,
      party: party,
      lines: [line('l1', 'Meal', amount)],
      assign: {'l1': party},
    );

void main() {
  const party = ['you', 'a', 'b'];

  test('nothing paid yet means no progress', () {
    final g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'you', amount: 30, party: party),
    ]);
    final p = receiptPayments(g)['r1']!;
    expect(p.owedCents, 2000); // a and b owe 10 each
    expect(p.paidCents, 0);
    expect(p.progress, PaymentProgress.none);
  });

  test('one of two paying is partial', () {
    var g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'you', amount: 30, party: party),
    ]);
    g = g.copyWith(
        settlements: [const Settlement(from: 'a', to: 'you', cents: 1000)]);

    final p = receiptPayments(g)['r1']!;
    expect(p.progress, PaymentProgress.partial);
    expect(p.paidCents, 1000);
    expect(p.outstandingCents, 1000);
    expect(p.settledBy, {'a'});
    expect(p.debtors, {'a', 'b'});
  });

  test('everyone paying marks the whole receipt paid', () {
    var g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'you', amount: 30, party: party),
    ]);
    g = g.copyWith(settlements: const [
      Settlement(from: 'a', to: 'you', cents: 1000),
      Settlement(from: 'b', to: 'you', cents: 1000),
    ]);

    final p = receiptPayments(g)['r1']!;
    expect(p.progress, PaymentProgress.full);
    expect(p.outstandingCents, 0);
    expect(p.settledBy, {'a', 'b'});
  });

  test('a part payment from one person is still partial', () {
    var g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'you', amount: 30, party: party),
    ]);
    g = g.copyWith(
        settlements: [const Settlement(from: 'a', to: 'you', cents: 400)]);

    final p = receiptPayments(g)['r1']!;
    expect(p.progress, PaymentProgress.partial);
    expect(p.settledBy, isEmpty, reason: 'a has not covered their full share');
    expect(p.paidCents, 400);
    expect(p.outstandingCents, 1600);
  });

  test('a payment spills onto the next bill once the first is clear', () {
    var g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'you', amount: 30, party: party),
      dinner(id: 'r2', paidBy: 'you', amount: 60, party: party),
    ]);
    // a owes 10 on r1 and 20 on r2, and pays 25.
    g = g.copyWith(
        settlements: [const Settlement(from: 'a', to: 'you', cents: 2500)]);

    final payments = receiptPayments(g);
    expect(payments['r1']!.settledBy, {'a'},
        reason: 'the oldest bill is cleared first');
    expect(payments['r2']!.settledBy, isEmpty);
    expect(payments['r2']!.progress, PaymentProgress.partial);
  });

  test('offsetting covers a share without anybody paying for it', () {
    // you paid dinner, a paid the taxi. Their debts partly cancel without
    // anybody handing over money.
    final g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'you', amount: 30, party: party),
      dinner(id: 'r2', paidBy: 'a', amount: 30, party: party),
    ]);

    final payments = receiptPayments(g);
    // a owes 10 on r1 but is owed 20 on r2, so a is square and their share of
    // r1 counts as covered.
    expect(payments['r1']!.settledBy, contains('a'));
    // b has paid nothing and owes on both.
    expect(payments['r1']!.settledBy, isNot(contains('b')));

    // But no money has changed hands, so the bill must not claim it has.
    expect(payments['r1']!.cashCents, 0);
    expect(payments['r1']!.progress, PaymentProgress.none,
        reason: 'offsetting is not a payment');
  });

  test('no settlement anywhere means no bill is ever badged', () {
    // The reported bug: bills read "Part paid" before anybody had paid.
    // Ben owes 50 on the dinner Ana fronted, and fronted 30 of the taxi
    // himself, so 30 of his debt cancels out. Nobody has handed over a penny.
    final g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'a', amount: 100, party: const ['a', 'b']),
      dinner(id: 'r2', paidBy: 'b', amount: 60, party: const ['a', 'b']),
    ]);

    final payments = receiptPayments(g);
    expect(payments['r1']!.paidCents, 3000, reason: 'offset by the taxi');
    expect(payments['r1']!.cashCents, 0);
    for (final r in g.receipts) {
      expect(payments[r.id]!.progress, PaymentProgress.none,
          reason: '${r.id} shows a badge with nothing paid');
    }
  });

  test('part paid appears as soon as real money moves', () {
    var g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'a', amount: 100, party: const ['a', 'b']),
      dinner(id: 'r2', paidBy: 'b', amount: 60, party: const ['a', 'b']),
    ]);
    // Ben owes 20 net. He hands over 5 of it.
    g = g.copyWith(
        settlements: [const Settlement(from: 'b', to: 'a', cents: 500)]);

    final p = receiptPayments(g)['r1']!;
    expect(p.cashCents, 500);
    expect(p.progress, PaymentProgress.partial);

    // And paying the rest squares the bill off.
    g = g.copyWith(settlements: [
      ...g.settlements,
      const Settlement(from: 'b', to: 'a', cents: 1500),
    ]);
    expect(receiptPayments(g)['r1']!.progress, PaymentProgress.full);
  });

  test('a bill paid in cash stays paid when a later bill is added', () {
    // The badge used to be derived by differencing the payer's whole-group
    // net before and after settling. Once a later bill pushed them into
    // credit, that difference collapsed to zero and a bill somebody really
    // had handed cash over for quietly stopped saying so.
    var g = Group(
      id: 'g',
      name: 'Trip',
      receipts: [dinner(id: 'r1', paidBy: 'you', amount: 20, party: const ['you', 'a'])],
    );
    g = g.copyWith(
      settlements: const [Settlement(from: 'a', to: 'you', cents: 1000)],
    );
    expect(receiptPayments(g)['r1']!.progress, PaymentProgress.full);

    // Ana now fronts the taxi. Her €10 for the dinner did not un-happen.
    g = g.copyWith(
      receipts: [
        ...g.receipts,
        dinner(id: 'r2', paidBy: 'a', amount: 20, party: const ['you', 'a']),
      ],
    );

    final p = receiptPayments(g)['r1']!;
    expect(p.cashCents, 1000, reason: 'Ana really did hand over €10');
    expect(p.progress, PaymentProgress.full,
        reason: 'a later bill must not un-pay an earlier one');
  });

  test('clearing every transfer marks every bill paid', () {
    var g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'you', amount: 30, party: party),
      dinner(id: 'r2', paidBy: 'a', amount: 30, party: party),
      dinner(id: 'r3', paidBy: 'b', amount: 60, party: party),
    ]);

    for (final t in aggregate(g, (id) => id).transfers) {
      g = g.copyWith(settlements: [
        ...g.settlements,
        Settlement(from: t.from, to: t.to, cents: t.cents),
      ]);
    }

    final payments = receiptPayments(g);
    for (final r in g.receipts) {
      expect(payments[r.id]!.progress, PaymentProgress.full,
          reason: 'everyone is square, so ${r.id} is paid off');
    }
    expect(aggregate(g, (id) => id).allSquare, isTrue);
  });

  test('a bill the payer covered alone has nothing to settle', () {
    final g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'you', amount: 8.90, party: const ['you']),
    ]);
    final p = receiptPayments(g)['r1']!;
    expect(p.nothingToSettle, isTrue);
    expect(p.progress, PaymentProgress.none);
  });

  test('a bill nobody has paid towards shows no progress', () {
    final g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'you', amount: 30, party: party),
    ]);
    expect(receiptPayments(g)['r1']!.progress, PaymentProgress.none);
  });

  test('showing progress does not disturb the group nets', () {
    var g = Group(id: 'g', name: 'Trip', receipts: [
      dinner(id: 'r1', paidBy: 'you', amount: 30, party: party),
    ]);
    g = g.copyWith(settlements: const [
      Settlement(from: 'a', to: 'you', cents: 1000),
      Settlement(from: 'b', to: 'you', cents: 1000),
    ]);

    final totals = aggregate(g, (id) => id);
    expect(receiptPayments(g)['r1']!.progress, PaymentProgress.full);
    // Everyone square, and the money still adds up.
    expect(totals.people.fold(0, (s, p) => s + p.netCents), 0);
    expect(totals.allSquare, isTrue);
    expect(totals.transfers, isEmpty);
  });
}
