import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<AppState> toSummary(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
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
  await tapText('Trattoria Bella');
  await tapText('Edit this receipt');
  await tapText('Next · who had what?');
  await tapText('See the summary');
  return state;
}

void main() {
  testWidgets('a brand new receipt is saved by the group chip too',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
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

    final before = state.groupById('lisbon')!.receipts.length;

    await tapText('Split a new bill');
    await tapText('Lisbon trip');
    await tapText('Next · scan the bill');
    await tapText('Gallery');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tapText('Next · who had what?');
    await tapText('Split equally');
    await tapText('See the summary');
    await tester.tap(find.textContaining('see the group total'));
    await tester.pumpAndSettle();

    expect(state.draft, isNull);
    expect(state.groupById('lisbon')!.receipts.length, before + 1);
    expect(find.text('Group summary'), findsOneWidget);
  });

  testWidgets('the group chip saves the receipt before navigating',
      (tester) async {
    final state = await toSummary(tester);

    // Change something on this screen, so there is work to lose.
    state.setPaidBy('f2');
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('see the group total'));
    await tester.pumpAndSettle();

    // The draft is written back into the group, not dropped.
    expect(state.draft, isNull);
    final saved = state
        .groupById('lisbon')!
        .receipts
        .firstWhere((r) => r.id == 'live');
    expect(saved.paidBy, 'f2');

    // And we actually land on the group summary.
    expect(find.text('Group summary'), findsOneWidget);
  });

  testWidgets('Done saves it too', (tester) async {
    final state = await toSummary(tester);
    state.setPaidBy('f3');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(state.draft, isNull);
    expect(
      state.groupById('lisbon')!.receipts.firstWhere((r) => r.id == 'live').paidBy,
      'f3',
    );
    expect(find.text('Split a new bill'), findsOneWidget);
  });
}
