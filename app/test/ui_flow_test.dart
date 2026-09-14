import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';

import 'fixtures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppState> pumpApp(WidgetTester tester) async {
  // The design targets a phone. Testing at the default 800x600 desktop
  // surface would exercise a layout the app is never shown at.
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final state = populated();
  await tester.pumpWidget(BillApp(state: state));
  await tester.pumpAndSettle();
  return state;
}


/// Scrolls the target into view before tapping. Several call-to-action
/// buttons now sit at the bottom of a scrolling body.
Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('home lists the seeded groups', (tester) async {
    await pumpApp(tester);
    expect(find.text('Split the bill in seconds.'), findsOneWidget);
    expect(find.text('Lisbon trip'), findsOneWidget);
    expect(find.text('Coffee run'), findsOneWidget);
    expect(find.text('Split a new bill'), findsOneWidget);
  });

  testWidgets('the whole six-step flow runs end to end', (tester) async {
    final state = await pumpApp(tester);

    await tapText(tester, 'Split a new bill');
    expect(find.textContaining('STEP 1 OF 6'), findsOneWidget);

    await tapText(tester, 'One-off split');
    expect(find.textContaining('STEP 2 OF 6'), findsOneWidget);

    // Bring a second person into the party so the split is real.
    await tapText(tester, 'Amara');
    expect(find.text('2 splitting, including you.'), findsOneWidget);

    await tapText(tester, 'Next · scan the bill');
    expect(find.textContaining('STEP 3 OF 6'), findsOneWidget);

    // The mock engine feeds a synthetic receipt through the real parser.
    await tester.tap(find.text('Gallery'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.textContaining('STEP 4 OF 6'), findsOneWidget);
    // The misread 65.00 tiramisu must trip the balance banner.
    expect(find.textContaining("Doesn't add up"), findsOneWidget);

    // The price-column filter must have rejected the date and phone number.
    final lines = state.draft!.receipt.lines;
    final phoneRow = lines.firstWhere((l) => l.rawText.contains('TEL'));
    expect(phoneRow.amount, isNull);

    await tapText(tester, 'Next · who had what?');
    expect(find.textContaining('STEP 5 OF 6'), findsOneWidget);
    expect(find.text('Split equally'), findsOneWidget);

    await tapText(tester, 'Split equally');
    expect(find.text('Clear all'), findsOneWidget);

    await tapText(tester, 'See the summary');
    expect(find.textContaining('STEP 6 OF 6'), findsOneWidget);
    expect(find.text('This receipt'), findsOneWidget);

    await tapText(tester, 'Done');

    // The finished receipt is now a real record in a one-off group.
    expect(state.draft, isNull);
    expect(state.groups.where((g) => g.oneOff).length, 1);
  });

  testWidgets('correcting the misread amount makes the receipt balance',
      (tester) async {
    final state = await pumpApp(tester);
    state.editReceipt('lisbon', 'live');
    await tester.pumpAndSettle();

    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Trattoria Bella');
    await tapText(tester, 'Edit this receipt');

    expect(find.textContaining("Doesn't add up"), findsOneWidget);

    await tapText(tester, 'T1ramisu');
    expect(find.textContaining('T1RAMISU 65.00'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '65.00'), '6.50');
    await tapText(tester, 'Done');

    expect(find.textContaining('Adds up'), findsOneWidget);
  });

  testWidgets('group summary settles everyone to zero', (tester) async {
    final state = await pumpApp(tester);

    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Group summary · who owes what overall');

    expect(find.text('SETTLE UP · FEWEST PAYMENTS'), findsOneWidget);

    final totals = state.totalsFor(state.groupById('lisbon')!);
    expect(totals.people.fold(0, (s, p) => s + p.netCents), 0);

    // Pay off every transfer and the card should empty out.
    for (final t in totals.transfers) {
      state.recordSettlement('lisbon', t.from, t.to, t.cents);
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing owed'), findsOneWidget);
  });

  testWidgets('dark mode repaints the app', (tester) async {
    final state = await pumpApp(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    await tapText(tester, 'Dark');
    expect(state.settings.dark, isTrue);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.backgroundColor, const Color(0xFF14181F));
  });

  testWidgets('refuses to remove a friend who is on a bill', (tester) async {
    final state = await pumpApp(tester);
    state.removeFriend('f1'); // Amara is all over the Lisbon receipts
    await tester.pumpAndSettle();
    expect(state.friends.any((f) => f.id == 'f1'), isTrue);
    expect(find.textContaining("Can't remove Amara"), findsOneWidget);
  });
}
