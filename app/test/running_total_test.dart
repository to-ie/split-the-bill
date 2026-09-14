import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<AppState> openCheck(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final state = populated();
  await tester.pumpWidget(BillApp(state: state));
  await tester.pumpAndSettle();

  state.editReceipt('lisbon', 'live');
  await tester.pumpAndSettle();

  await tester.tap(find.text('Lisbon trip'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Trattoria Bella'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Edit this receipt'));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('the running total is broken out by kind', (tester) async {
    await openCheck(tester);

    expect(find.text('ITEMS'), findsOneWidget);
    expect(find.text('EXTRAS'), findsOneWidget);
    expect(find.text('YOUR TOTAL'), findsOneWidget);

    // Items 105.50 (the tiramisu is misread as 65.00) plus 4.70 service.
    expect(find.text('€105.50'), findsOneWidget);
    expect(find.text('€4.70'), findsWidgets);
    expect(find.text('€110.20'), findsOneWidget);
  });

  testWidgets('it says how far off the printed total is', (tester) async {
    await openCheck(tester);
    expect(
      find.textContaining('more than the printed total'),
      findsOneWidget,
    );
  });

  testWidgets('it follows the keystrokes, not just Done', (tester) async {
    final state = await openCheck(tester);

    await tester.tap(find.text('T1ramisu'));
    await tester.pumpAndSettle();

    // Type the correction but do NOT press Done.
    await tester.enterText(find.widgetWithText(TextField, '65.00'), '6.50');
    await tester.pumpAndSettle();

    expect(state.draft!.receipt.itemsCents, 4700);
    expect(find.text('€47.00'), findsWidgets);
    expect(find.text('€51.70'), findsWidgets);
    expect(find.textContaining('Matches the printed total'), findsOneWidget);
  });

  testWidgets('a discount pulls the total down', (tester) async {
    final state = await openCheck(tester);

    await tester.tap(find.text('Service charge 10%'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discount (-)'));
    await tester.pumpAndSettle();

    expect(state.draft!.receipt.discountsCents, -470);
    expect(find.text('DISCOUNTS'), findsOneWidget);
    expect(find.text('EXTRAS'), findsNothing);
    // 105.50 items - 4.70 discount.
    expect(find.text('€100.80'), findsOneWidget);
  });
}
