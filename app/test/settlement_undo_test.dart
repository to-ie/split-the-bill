import 'package:bill/app.dart';
import 'package:bill/logic/receipt_payments.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<AppState> openGroupSummary(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final state = populated();
  await tester.pumpWidget(BillApp(state: state));
  await tester.pumpAndSettle();

  Future<void> tapText(String text) async {
    final f = find.text(text);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  await tapText('Lisbon trip');
  await tapText('Group summary · who owes what overall');
  return state;
}

void main() {
  testWidgets('marking a payment paid can be undone again', (tester) async {
    final state = await openGroupSummary(tester);

    final before = state.totalsFor(state.groupById('lisbon')!);
    expect(before.transfers, isNotEmpty);
    final first = before.transfers.first;

    await tester.ensureVisible(find.text('Mark paid').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark paid').first);
    await tester.pumpAndSettle();

    expect(state.groupById('lisbon')!.settlements.length, 1);
    expect(find.text('PAYMENTS RECORDED'), findsOneWidget);

    await tester.ensureVisible(find.text('Undo').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo').first);
    await tester.pumpAndSettle();

    expect(state.groupById('lisbon')!.settlements, isEmpty);
    expect(find.text('PAYMENTS RECORDED'), findsNothing);

    // The debt is back exactly as it was.
    final after = state.totalsFor(state.groupById('lisbon')!);
    expect(after.transfers.length, before.transfers.length);
    expect(after.transfers.first.from, first.from);
    expect(after.transfers.first.to, first.to);
    expect(after.transfers.first.cents, first.cents);
  });

  testWidgets('undo takes back the payment that was tapped', (tester) async {
    final state = await openGroupSummary(tester);

    state.recordSettlement('lisbon', 'f1', 'you', 500);
    state.recordSettlement('lisbon', 'f1', 'you', 900);
    await tester.pumpAndSettle();
    expect(state.groupById('lisbon')!.settlements.length, 2);

    // Undo the first of the two, not merely the most recent.
    state.undoSettlementRecord(
      'lisbon',
      state.groupById('lisbon')!.settlements.first,
    );
    await tester.pumpAndSettle();

    final left = state.groupById('lisbon')!.settlements;
    expect(left.length, 1);
    expect(left.single.cents, 900);
  });

  testWidgets('a paid-off bill is badged, and the badge goes on undo',
      (tester) async {
    final state = await openGroupSummary(tester);

    // Clear every transfer, which pays off every bill.
    for (final t in state.totalsFor(state.groupById('lisbon')!).transfers) {
      state.recordSettlement('lisbon', t.from, t.to, t.cents);
    }
    await tester.pumpAndSettle();

    final payments = receiptPayments(state.groupById('lisbon')!);
    expect(payments['r1']!.progress, PaymentProgress.full);

    await tester.tap(find.bySemanticsLabel('Back').first);
    await tester.pumpAndSettle();
    expect(find.text('Paid'), findsWidgets);

    // Undo one payment and a bill drops back to part paid.
    state.undoSettlementRecord(
      'lisbon',
      state.groupById('lisbon')!.settlements.last,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Part paid'), findsWidgets);
  });
}
