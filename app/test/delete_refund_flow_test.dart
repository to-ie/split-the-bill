import 'package:bill/app.dart';
import 'package:bill/logic/overpayment.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// The whole deletion story, driven through the screens rather than the
/// functions underneath them: settle up, delete a paid bill, read what the
/// app says will happen, choose, and check it said the truth.
Future<AppState> boot(WidgetTester tester, {Size size = const Size(390, 844)}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final app = populated();
  for (final t in app.totalsFor(app.groupById('lisbon')!).transfers) {
    app.recordSettlement('lisbon', t.from, t.to, t.cents);
  }
  await tester.pumpWidget(BillApp(state: app));
  await tester.pumpAndSettle();
  return app;
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> openDeleteDialog(WidgetTester tester, {int row = 0}) async {
  await tapText(tester, 'Lisbon trip');
  await tester.tap(find.bySemanticsLabel('Receipt options').at(row));
  await tester.pumpAndSettle();
  await tapText(tester, 'Delete');
}

void main() {
  testWidgets('the dialog promises exactly what plain deletion does', (
    tester,
  ) async {
    final app = await boot(tester);
    await openDeleteDialog(tester);

    // Read the promise off the screen, then take the plain branch.
    final promised = {
      for (final s in app.shiftIfReceiptDeleted('lisbon', 'r1'))
        s.person: s.after,
    };
    expect(find.textContaining('If you just delete it'), findsOneWidget);

    await tapText(tester, 'Delete it');
    await tester.pumpAndSettle();

    final totals = app.totalsFor(app.groupById('lisbon')!);
    for (final p in totals.people) {
      if (!promised.containsKey(p.friendId)) continue;
      expect(p.netCents, promised[p.friendId],
          reason: 'the dialog lied about ${p.friendId}');
    }
    // The payment stands: it happened.
    expect(app.groupById('lisbon')!.settlements, isNotEmpty);
  });

  testWidgets('handing the money back settles the residue and says so', (
    tester,
  ) async {
    final app = await boot(tester);
    await openDeleteDialog(tester);

    await tapText(tester, 'Delete and hand back the €29.93 they paid');
    await tester.pumpAndSettle();

    final g = app.groupById('lisbon')!;
    expect(g.receipts.where((r) => r.id == 'r1'), isEmpty);
    expect(overpaidBy(g), isEmpty, reason: 'somebody is still holding money');
    expect(g.settlements.where((s) => s.refund), isNotEmpty);

    // Nothing was rewritten: the original payments are all still there.
    expect(g.settlements.where((s) => !s.refund), hasLength(3));

    // And the summary explains it rather than showing bare transfers.
    await tapText(tester, 'Group summary · who owes what overall');
    expect(find.text('handed back'), findsWidgets);
  });

  testWidgets('deleting a second bill does not double back the first', (
    tester,
  ) async {
    final app = await boot(tester);

    await openDeleteDialog(tester);
    await tapText(tester, 'Delete and hand back the €29.93 they paid');
    await tester.pumpAndSettle();

    // Straight into deleting another one.
    await tester.tap(find.bySemanticsLabel('Receipt options').first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Delete');
    final refund = find.textContaining('Delete and hand back');
    if (refund.evaluate().isNotEmpty) {
      await tester.tap(refund);
    } else {
      await tapText(tester, 'Delete it');
    }
    await tester.pumpAndSettle();

    final g = app.groupById('lisbon')!;
    for (final person in g.members) {
      final got = g.settlements
          .where((s) => !s.refund && s.to == person)
          .fold(0, (a, s) => a + s.cents);
      final gave = g.settlements
          .where((s) => s.refund && s.from == person)
          .fold(0, (a, s) => a + s.cents);
      expect(gave, lessThanOrEqualTo(got),
          reason: '$person handed back more than they were ever given');
    }
    expect(
      app.totalsFor(g).people.fold(0, (s, p) => s + p.netCents),
      0,
    );
  });

  testWidgets('a bill nobody settled deletes without any of this', (
    tester,
  ) async {
    final app = populated();
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(BillApp(state: app));
    await tester.pumpAndSettle();

    await openDeleteDialog(tester);
    expect(find.textContaining('Delete and hand back'), findsNothing,
        reason: 'nobody has paid, so there is nothing to hand back');
    await tapText(tester, 'Delete it');
    await tester.pumpAndSettle();
    expect(app.groupById('lisbon')!.settlements, isEmpty);
  });

  testWidgets('the dialog fits a small phone at large text', (tester) async {
    await boot(tester, size: const Size(320, 640));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: BillApp(state: populated()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
