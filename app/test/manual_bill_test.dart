import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Not every bill comes with a receipt: it was lost, never issued, or the
/// evening is being reconstructed afterwards. Typing one in has to reach the
/// same place a scan does.
Future<AppState> open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final app = populated();
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

void main() {
  testWidgets('typing a bill in reaches the same check screen', (tester) async {
    final app = await open(tester);

    await tapText(tester, 'Split a new bill');
    await tapText(tester, 'One-off split');
    await tapText(tester, 'Amara');
    await tapText(tester, 'Next · scan the bill');

    expect(find.text('Type it in'), findsOneWidget);
    await tapText(tester, 'Type it in');

    expect(app.draft!.manual, isTrue);
    expect(app.draft!.receipt.lines, isEmpty);
    expect(app.draft!.receipt.name, isNotEmpty,
        reason: 'a nameless bill shows as a blank line everywhere it appears');
    expect(find.textContaining('An empty bill'), findsOneWidget);
    expect(find.textContaining('Nothing was read from this photo'), findsNothing);

    // And it is a working bill: add a line and the total follows.
    await tapText(tester, '+ Add an item');
    await tester.enterText(find.byType(TextField).last, '12.50');
    await tester.pumpAndSettle();
    expect(app.draft!.receipt.grandCents, 1250);
  });

  testWidgets('the scan screen is gone once the bill is typed in', (
    tester,
  ) async {
    await open(tester);
    await tapText(tester, 'Split a new bill');
    await tapText(tester, 'One-off split');
    await tapText(tester, 'Amara');
    await tapText(tester, 'Next · scan the bill');
    await tapText(tester, 'Type it in');

    // pushReplacement, so going back does not land on a viewfinder for a
    // receipt that does not exist.
    expect(find.text('Scan the bill'), findsNothing);
  });

  testWidgets('a failed scan still says the scan failed', (tester) async {
    final app = await open(tester);
    app.startFlow();
    app.setDestination(null);
    expect(app.draft!.manual, isFalse);
  });
}
