import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Finishing a bill lands on the group it belongs to, not back at the start.
/// The question anybody has after adding a receipt is what it did to the
/// totals, and the work has to be saved before they get there.
Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<AppState> boot(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final state = populated();
  await tester.pumpWidget(BillApp(state: state));
  await tester.pumpAndSettle();
  return state;
}

/// Reopens an existing receipt and walks it back to the last step.
Future<AppState> toSummary(WidgetTester tester) async {
  final state = await boot(tester);
  await tapText(tester, 'Lisbon trip');
  await tapText(tester, 'Trattoria Bella');
  await tapText(tester, 'Edit this receipt');
  await tapText(tester, 'Next · who had what?');
  await tapText(tester, 'See the summary');
  return state;
}

void main() {
  testWidgets('a brand new receipt is saved, and Done shows the group', (
    tester,
  ) async {
    final state = await boot(tester);
    final before = state.groupById('lisbon')!.receipts.length;

    await tapText(tester, 'Split a new bill');
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Next · scan the bill');
    await tapText(tester, 'Gallery');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tapText(tester, 'Next · who had what?');
    await tapText(tester, 'Split equally');
    await tapText(tester, 'See the summary');
    await tapText(tester, 'Done');

    expect(state.draft, isNull);
    expect(state.groupById('lisbon')!.receipts.length, before + 1);
    expect(find.text('Group summary'), findsOneWidget);
  });

  testWidgets('Done saves the work on the last screen before moving on', (
    tester,
  ) async {
    final state = await toSummary(tester);

    // Change something here, so there is work to lose.
    state.setPaidBy('f2');
    await tester.pumpAndSettle();

    await tapText(tester, 'Done');

    expect(state.draft, isNull);
    final saved = state.groupById('lisbon')!.receipts.firstWhere(
      (r) => r.id == 'live',
    );
    expect(saved.paidBy, 'f2');
    expect(find.text('Group summary'), findsOneWidget);
  });

  testWidgets('the group summary it lands on is the right one', (tester) async {
    await toSummary(tester);
    await tapText(tester, 'Done');
    expect(find.text('Group summary'), findsOneWidget);
    expect(find.textContaining('Lisbon trip'), findsWidgets);
  });

  testWidgets('a one-off split has no group worth showing, so Done goes home', (
    tester,
  ) async {
    final state = await boot(tester);

    await tapText(tester, 'Split a new bill');
    await tapText(tester, 'One-off split');
    await tapText(tester, 'Amara');
    await tapText(tester, 'Next · scan the bill');
    await tapText(tester, 'Gallery');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tapText(tester, 'Next · who had what?');
    await tapText(tester, 'Split equally');
    await tapText(tester, 'See the summary');
    await tapText(tester, 'Done');

    expect(state.draft, isNull);
    expect(find.text('Split a new bill'), findsOneWidget);
    expect(find.text('Group summary'), findsNothing);
  });

  testWidgets('the summary says where the bill has landed', (tester) async {
    await toSummary(tester);
    expect(find.textContaining('Part of Lisbon trip'), findsOneWidget);
    // And no longer offers a second way to do what Done does.
    expect(find.textContaining('see the group total'), findsNothing);
  });
}
