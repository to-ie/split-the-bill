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
  return state;
}

Future<void> swipeLeft(WidgetTester tester, String label) async {
  await tester.drag(find.text(label), const Offset(-500, 0));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('swiping a line removes it, and the total follows',
      (tester) async {
    final state = await openCheck(tester);
    final before = state.draft!.receipt.itemsCents;

    await swipeLeft(tester, 'Burrata');

    expect(find.text('Burrata'), findsNothing);
    expect(state.draft!.receipt.lines.any((l) => l.id == 'i1'), isFalse);
    expect(state.draft!.receipt.itemsCents, before - 800);
  });

  testWidgets('nothing stands between the swipe and the deletion',
      (tester) async {
    await openCheck(tester);
    await swipeLeft(tester, 'Burrata');
    expect(find.text('Delete this line?'), findsNothing,
        reason: 'the swipe is deliberate enough on its own');
  });

  testWidgets('deleting a line drops its assignments too', (tester) async {
    final state = await openCheck(tester);
    expect(state.draft!.receipt.assign.containsKey('i1'), isTrue);

    await swipeLeft(tester, 'Burrata');

    expect(state.draft!.receipt.assign.containsKey('i1'), isFalse);
  });

  testWidgets('swiping the other way does nothing', (tester) async {
    final state = await openCheck(tester);
    final before = state.draft!.receipt.lines.length;

    await tester.drag(find.text('Burrata'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete this line?'), findsNothing);
    expect(state.draft!.receipt.lines.length, before);
  });

  testWidgets('a tap still opens the editor rather than deleting',
      (tester) async {
    await openCheck(tester);
    await tester.tap(find.text('Burrata'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Description'), findsOneWidget);
    expect(find.text('Delete this line?'), findsNothing);
  });
}
