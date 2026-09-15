import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';

import 'fixtures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// flutter_test ships a placeholder font that draws every glyph as a box, so
/// the bundled fonts have to be loaded by hand for a screenshot to be worth
/// looking at.
Future<void> loadFonts() async {
  for (final family in ['Nunito', 'RobotoMono']) {
    final loader = FontLoader(family)
      ..addFont(rootBundle.load('assets/fonts/$family.ttf'));
    await loader.load();
  }
  // Without this every icon draws as an empty box.
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

/// Renders every screen to a PNG under test/goldens/ so the layout can be
/// checked by eye at the size the design targets.
///
/// Regenerate with:  flutter test --update-goldens test/screenshot_test.dart
Future<AppState> boot(WidgetTester tester,
    {bool dark = false, bool empty = false}) async {
  tester.view.physicalSize = const Size(1080, 2160);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final state = empty ? AppState.ephemeral() : populated();
  if (empty) await state.load();
  if (dark) state.setDark(true);

  // Image decoding is genuinely asynchronous, so it needs a real event loop.
  await tester.runAsync(loadFonts);

  await tester.pumpWidget(BillApp(state: state));

  // Wait for the logo to be decoded and in the cache, rather than sleeping
  // and hoping. A fixed delay here passed when this file ran on its own and
  // failed when the whole suite ran, because the machine was busy and the
  // frame was captured before the artwork had painted.
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/images/logo.png'),
      tester.element(find.byType(MaterialApp)),
    );
  });

  await tester.pumpAndSettle();
  return state;
}

Future<void> shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

Future<void> tapText(WidgetTester tester, String text) async {
  // Scroll it into view first: several calls to action sit at the foot of a
  // scrolling body, and a tap that misses fails silently.
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('01 home', (tester) async {
    await boot(tester);
    await shot(tester, '01_home');
  });

  testWidgets('02 destination', (tester) async {
    await boot(tester);
    await tapText(tester, 'Split a new bill');
    await shot(tester, '02_destination');
  });

  testWidgets('03 people', (tester) async {
    await boot(tester);
    await tapText(tester, 'Split a new bill');
    await tapText(tester, 'One-off split');
    await tapText(tester, 'Amara');
    await shot(tester, '03_people');
  });

  testWidgets('00 first run, nothing in it yet', (tester) async {
    await boot(tester, empty: true);
    await shot(tester, '00_home_empty');
  });

  testWidgets('04 scan', (tester) async {
    await boot(tester);
    await tapText(tester, 'Split a new bill');
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Next · scan the bill');
    await shot(tester, '04_scan');
  });

  testWidgets('05 check', (tester) async {
    final state = await boot(tester);
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Trattoria Bella');
    await tapText(tester, 'Edit this receipt');
    await shot(tester, '05_check');
    expect(state.draft, isNotNull);
  });

  testWidgets('06 check, row being edited', (tester) async {
    await boot(tester);
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Trattoria Bella');
    await tapText(tester, 'Edit this receipt');
    await tapText(tester, 'T1ramisu');
    await shot(tester, '06_check_editing');
  });

  testWidgets('05b check, foot of the receipt', (tester) async {
    await boot(tester);
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Trattoria Bella');
    await tapText(tester, 'Edit this receipt');
    await tester.ensureVisible(find.text('YOUR TOTAL'));
    await tester.pumpAndSettle();
    await shot(tester, '05b_check_total');
  });

  testWidgets('05c check, a line part-swiped', (tester) async {
    await boot(tester);
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Trattoria Bella');
    await tapText(tester, 'Edit this receipt');
    // Held part way, so the red panel behind it is visible.
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Burrata')));
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    await shot(tester, '05c_check_delete');
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('07 assign', (tester) async {
    await boot(tester);
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Trattoria Bella');
    await tapText(tester, 'Edit this receipt');
    await tapText(tester, 'Next · who had what?');
    await shot(tester, '07_assign');
  });

  testWidgets('08 receipt summary', (tester) async {
    await boot(tester);
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Trattoria Bella');
    await tapText(tester, 'Edit this receipt');
    await tapText(tester, 'Next · who had what?');
    await tapText(tester, 'See the summary');
    await shot(tester, '08_receipt_summary');
  });

  testWidgets('09 group', (tester) async {
    await boot(tester);
    await tapText(tester, 'Lisbon trip');
    await shot(tester, '09_group');
  });

  testWidgets('10 receipt view', (tester) async {
    await boot(tester);
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Gelato by the river');
    await shot(tester, '10_receipt_view');
  });

  testWidgets('11 group summary', (tester) async {
    await boot(tester);
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Group summary · who owes what overall');
    await shot(tester, '11_group_summary');
  });

  testWidgets('11b group summary with a payment recorded', (tester) async {
    final state = await boot(tester);
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Group summary · who owes what overall');

    expect(find.text('Group summary'), findsOneWidget);
    final t = state.totalsFor(state.groupById('lisbon')!).transfers.first;
    state.recordSettlement('lisbon', t.from, t.to, t.cents);
    await tester.pumpAndSettle();
    expect(find.text('PAYMENTS RECORDED'), findsOneWidget);
    await shot(tester, '11b_group_summary_paid');
  });

  testWidgets('09b group with payment badges', (tester) async {
    final state = await boot(tester);
    for (final t in state.totalsFor(state.groupById('lisbon')!).transfers) {
      state.recordSettlement('lisbon', t.from, t.to, t.cents);
    }
    await tester.pumpAndSettle();
    await tapText(tester, 'Lisbon trip');
    await shot(tester, '09b_group_paid');
  });

  testWidgets('11d group summary holding money for a deleted bill', (
    tester,
  ) async {
    final state = await boot(tester);
    // Everybody settles up, and then one of the bills turns out to be a
    // duplicate and is deleted without handing the money back.
    for (final t in state.totalsFor(state.groupById('lisbon')!).transfers) {
      state.recordSettlement('lisbon', t.from, t.to, t.cents);
    }
    state.deleteReceipt('lisbon', 'r1');
    await tester.pumpAndSettle();

    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Group summary · who owes what overall');
    final banner = find.textContaining('no longer here').first;
    await tester.ensureVisible(banner);
    await tester.pumpAndSettle();
    expect(banner, findsOneWidget);
    await shot(tester, '11d_group_summary_overpaid');
  });

  testWidgets('09d deleting a bill somebody has settled', (tester) async {
    final state = await boot(tester);
    for (final t in state.totalsFor(state.groupById('lisbon')!).transfers) {
      state.recordSettlement('lisbon', t.from, t.to, t.cents);
    }
    await tester.pumpAndSettle();

    await tapText(tester, 'Lisbon trip');
    // Open the kebab on the first receipt, then Delete.
    await tester.tap(find.bySemanticsLabel('Receipt options').first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Delete');
    await tester.pumpAndSettle();

    expect(find.textContaining('If you just delete it'), findsOneWidget);
    expect(find.textContaining('You owe '), findsOneWidget);
    expect(find.textContaining('Delete and hand back'), findsOneWidget);
    await shot(tester, '09d_delete_settled_bill');
  });

  testWidgets('11c group summary with money unassigned', (tester) async {
    final state = await boot(tester);
    // Take the wine off everybody on the Trattoria bill.
    state.editReceipt('lisbon', 'live');
    for (final who in ['you', 'f1', 'f2', 'f3']) {
      if ((state.draft!.receipt.assign['i6'] ?? []).contains(who)) {
        state.toggleAssign('i6', who);
      }
    }
    state.discardDraftKeepingChanges();
    await tester.pumpAndSettle();

    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Group summary · who owes what overall');
    await shot(tester, '11c_group_summary_unassigned');
  });

  testWidgets('12 settings', (tester) async {
    await boot(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await shot(tester, '12_settings');
  });

  testWidgets('12b settings, foot of the page', (tester) async {
    await boot(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining(RegExp(r'Split the Bill \d')));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'Split the Bill \d')), findsOneWidget);
    await shot(tester, '12b_settings_foot');
  });

  testWidgets('09c a brand new group', (tester) async {
    final state = await boot(tester, empty: true);
    state.createGroup('Kithnos');
    await tester.pumpAndSettle();
    await tapText(tester, 'Kithnos');
    await shot(tester, '09c_group_empty');
  });

  testWidgets('13 archived', (tester) async {
    final state = await boot(tester);
    state.setArchived('cr', true);
    await tester.pumpAndSettle();
    await tapText(tester, 'Archived groups (1)');
    await shot(tester, '13_archived');
  });

  testWidgets('14 home in dark', (tester) async {
    await boot(tester, dark: true);
    await shot(tester, '14_home_dark');
  });

  testWidgets('15 group summary in dark', (tester) async {
    await boot(tester, dark: true);
    await tapText(tester, 'Lisbon trip');
    await tapText(tester, 'Group summary · who owes what overall');
    await shot(tester, '15_group_summary_dark');
  });
}
