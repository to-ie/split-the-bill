import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';
import 'package:bill/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<AppState> openSummary(WidgetTester tester) async {
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
  /// Only the contents of the settle up card, not the person cards below it
  /// which legitimately spell out names and amounts.
  Finder inSettleCard(Finder matching) => find.descendant(
        of: find.ancestor(
          of: find.text('SETTLE UP · FEWEST PAYMENTS'),
          matching: find.byType(BillCard),
        ),
        matching: matching,
      );

  testWidgets('the settle up row shows the amount, not the names',
      (tester) async {
    await openSummary(tester);

    expect(find.text('SETTLE UP · FEWEST PAYMENTS'), findsOneWidget);
    expect(inSettleCard(find.text('€30.92')), findsOneWidget);

    // The old wrapped "Tom pays You" label is gone.
    expect(inSettleCard(find.textContaining(' pays ')), findsNothing);
    expect(inSettleCard(find.textContaining('Tom')), findsNothing);
  });

  testWidgets('tapping a circle shows whose it is', (tester) async {
    await openSummary(tester);

    // Tom's name appears once, on his own card further down the page.
    final before = find.text('Tom').evaluate().length;

    await tester.tap(inSettleCard(find.text('T')).first);
    await tester.pumpAndSettle();

    // The tooltip adds a second one.
    expect(find.text('Tom').evaluate().length, before + 1);
  });

  testWidgets('a screen reader still gets the whole sentence', (tester) async {
    final handle = tester.ensureSemantics();
    await openSummary(tester);

    expect(
      find.bySemanticsLabel(RegExp(r'Tom pays You €30\.92')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('recorded payments read the same way', (tester) async {
    final state = await openSummary(tester);
    state.recordSettlement('lisbon', 'f2', 'you', 3092);
    await tester.pumpAndSettle();

    final inRecorded = find.descendant(
      of: find.ancestor(
        of: find.text('PAYMENTS RECORDED'),
        matching: find.byType(BillCard),
      ),
      matching: find.textContaining(' paid '),
    );

    expect(find.text('PAYMENTS RECORDED'), findsOneWidget);
    expect(inRecorded, findsNothing,
        reason: 'no "Tom paid You" label, just the amount');
    expect(find.text('Undo'), findsOneWidget);
  });
}
