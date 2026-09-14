import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// The menu behind the three dots used to be built on every tap and then
/// fail during layout, so it never appeared and nothing said why.
Future<AppState> openGroup(WidgetTester tester, {Size? size}) async {
  tester.view.physicalSize = size ?? const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final state = populated();
  await tester.pumpWidget(BillApp(state: state));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lisbon trip'));
  await tester.pumpAndSettle();
  return state;
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert).first);
  await tester.pumpAndSettle();
}

/// The kebab on a receipt row. Index 0 is the group's own menu in the header,
/// so the receipts start at 1. They sit below the fold on a short screen.
Future<void> openRowMenu(WidgetTester tester, int receipt) async {
  final kebab = find.byIcon(Icons.more_vert).at(receipt);
  await tester.ensureVisible(kebab);
  await tester.pumpAndSettle();
  await tester.tap(kebab);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the three dots show the options', (tester) async {
    await openGroup(tester);
    expect(find.text('Go to home'), findsNothing);

    await openMenu(tester);
    expect(find.text('Go to home'), findsOneWidget);
    expect(find.text('Currency'), findsOneWidget);
    expect(find.text('Archive this group'), findsOneWidget);
    expect(find.text('Delete this group'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'the menu used to throw during layout and render nothing');
  });

  testWidgets('it opens on a narrow screen too', (tester) async {
    await openGroup(tester, size: const Size(960, 2000));
    await openMenu(tester);
    expect(find.text('Archive this group'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archiving puts the group away and takes you home',
      (tester) async {
    final state = await openGroup(tester);
    await openMenu(tester);
    await tester.tap(find.text('Archive this group'));
    await tester.pumpAndSettle();

    expect(state.groupById('lisbon')!.archived, isTrue);
    expect(find.text('Split a new bill'), findsOneWidget,
        reason: 'staying on a group you have just filed away looks as '
            'though nothing happened');
    expect(find.text('Archived groups (1)'), findsOneWidget);
  });

  testWidgets('restoring leaves you on the group, ready to use it',
      (tester) async {
    final state = await openGroup(tester);
    state.setArchived('lisbon', true);
    await tester.pumpAndSettle();

    await openMenu(tester);
    await tester.tap(find.text('Restore this group'));
    await tester.pumpAndSettle();

    expect(state.groupById('lisbon')!.archived, isFalse);
    expect(find.text('RECEIPTS · MEALS, TICKETS, ANYTHING'), findsOneWidget);
  });

  testWidgets('tapping outside closes it', (tester) async {
    await openGroup(tester);
    await openMenu(tester);
    await tester.tapAt(const Offset(40, 600));
    await tester.pumpAndSettle();
    expect(find.text('Go to home'), findsNothing);
  });

  testWidgets('a receipt can be deleted, once confirmed', (tester) async {
    final state = await openGroup(tester);
    final before = state.groupById('lisbon')!.receipts.length;

    await openRowMenu(tester, 2);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this receipt?'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(state.groupById('lisbon')!.receipts.length, before);

    // Cancelling leaves the row's menu open, so it can be tried again
    // without hunting for the three dots a second time.
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete it'));
    await tester.pumpAndSettle();
    expect(state.groupById('lisbon')!.receipts.length, before - 1);
    expect(find.text('Gelato by the river'), findsNothing);
  });

  testWidgets('there is no mark-as-settled any more', (tester) async {
    await openGroup(tester);
    await openRowMenu(tester, 2);

    expect(find.textContaining('settled'), findsNothing,
        reason: 'clearing a bill is done by recording the payments that '
            'clear it, on the group summary');
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });
}
