import 'package:bill/app.dart';
import 'package:bill/logic/shares.dart';
import 'package:bill/model/models.dart';
import 'package:bill/parsing/receipt.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptLine item(String id, String desc, double amount) => ReceiptLine(
    id: id,
    description: desc,
    amount: amount,
    kind: LineKind.item,
    rawText: desc);

/// A dinner with the wine still belonging to nobody.
AppState withUnassignedWine() {
  final app = AppState.ephemeral();
  app.friends = const [
    Friend(id: 'you', name: 'You', color: 0xFF1E2749),
    Friend(id: 'a', name: 'Ana', color: 0xFF10A374),
  ];
  app.groups = [
    Group(id: 'g', name: 'Trip', receipts: [
      Receipt(
        id: 'r1',
        name: 'Dinner',
        date: '1 Jan',
        paidBy: 'you',
        party: const ['you', 'a'],
        lines: [item('l1', 'Mains', 20), item('l2', 'Wine', 10)],
        assign: const {
          'l1': ['you', 'a']
        },
      ),
    ]),
  ];
  return app;
}

Receipt stored(AppState app) => app.groupById('g')!.receipts.single;

void main() {
  group('an edit to a bill that already exists is saved as it is made', () {
    test('assigning a forgotten item sticks without walking to the end', () {
      final app = withUnassignedWine();
      expect(computeShares(stored(app)).unassignedCents, 1000);

      // What the amber banner does, then the user presses back.
      app.editReceipt('g', 'r1');
      app.toggleAssign('l2', 'you');
      app.toggleAssign('l2', 'a');

      expect(computeShares(stored(app)).unassignedCents, 0,
          reason: 'the assignment used to live only in the draft and was '
              'thrown away on the way out');
      expect(stored(app).assign['l2'], ['you', 'a']);
    });

    test('the group totals pick it up', () {
      final app = withUnassignedWine();
      final before = app.totalsFor(app.groupById('g')!);
      expect(before.outstandingCents, 1000); // half of the mains only

      app.editReceipt('g', 'r1');
      app.toggleAssign('l2', 'you');
      app.toggleAssign('l2', 'a');

      final after = app.totalsFor(app.groupById('g')!);
      expect(after.outstandingCents, 1500,
          reason: 'Ana now owes half the wine as well');
      expect(after.unassigned, isEmpty);
    });

    test('editing other fields sticks too', () {
      final app = withUnassignedWine();
      app.editReceipt('g', 'r1');
      app.setBillName('Taverna');
      app.setPaidBy('a');

      expect(stored(app).name, 'Taverna');
      expect(stored(app).paidBy, 'a');
    });

    test('discarding puts the bill back as it was', () {
      final app = withUnassignedWine();
      final before = stored(app);

      app.editReceipt('g', 'r1');
      app.setBillName('Taverna');
      app.toggleAssign('l2', 'you');
      expect(stored(app).name, 'Taverna');

      app.discardDraft();

      expect(stored(app).name, before.name);
      expect(stored(app).assign, before.assign);
      expect(app.draft, isNull);
    });

    test('a brand new bill is still only saved at the end', () {
      final app = withUnassignedWine();
      app.startFlow();
      app.setDestination('g');
      app.setBillName('Breakfast');

      expect(app.groupById('g')!.receipts.length, 1,
          reason: 'a bill being created has not been added to the group yet');
      app.finishFlow();
      expect(app.groupById('g')!.receipts.length, 2);
    });
  });

  group('settling up is refused while money belongs to nobody', () {
    Future<AppState> openSummary(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final app = withUnassignedWine();
      await tester.pumpWidget(BillApp(state: app));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();
      final cta = find.text('Group summary · who owes what overall');
      await tester.ensureVisible(cta);
      await tester.pumpAndSettle();
      await tester.tap(cta);
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('Mark paid does nothing and says why', (tester) async {
      final app = await openSummary(tester);

      expect(find.textContaining('is not assigned to anyone yet'),
          findsOneWidget);
      expect(find.textContaining('Finish assigning the items above'),
          findsOneWidget);

      await tester.tap(find.text('Mark paid'));
      await tester.pumpAndSettle();

      expect(app.groupById('g')!.settlements, isEmpty,
          reason: 'recording a payment against a figure known to be short '
              'bakes in the mistake');
      expect(find.textContaining('Assign everything on the bill'),
          findsOneWidget);
    });

    testWidgets('once everything is assigned it works again', (tester) async {
      final app = await openSummary(tester);

      app.editReceipt('g', 'r1');
      app.toggleAssign('l2', 'you');
      app.toggleAssign('l2', 'a');
      app.discardDraftKeepingChanges();
      await tester.pumpAndSettle();

      expect(find.textContaining('is not assigned to anyone yet'), findsNothing);
      await tester.tap(find.text('Mark paid'));
      await tester.pumpAndSettle();

      expect(app.groupById('g')!.settlements.length, 1);
      expect(app.groupById('g')!.settlements.single.cents, 1500);
    });
  });
}
