import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// A short viewport, so the last lines of the receipt are genuinely below the
/// fold and the editor has to be scrolled up to be usable.
Future<AppState> openCheck(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 1600);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final state = populated();
  await tester.pumpWidget(BillApp(state: state));
  await tester.pumpAndSettle();

  Future<void> tapText(String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  await tapText('Lisbon trip');
  await tapText('Trattoria Bella');
  await tapText('Edit this receipt');
  return state;
}

/// Everything the editor needs on screen at once.
void expectEditorUsable(WidgetTester tester, double visibleBottom) {
  final editor = find.byType(TextField).first;
  final box = tester.getRect(editor);
  expect(box.top, greaterThanOrEqualTo(0.0),
      reason: 'the editor is off the top of the screen');
  expect(box.bottom, lessThanOrEqualTo(visibleBottom),
      reason: 'the editor is under the keyboard');

  // Done and the kind chips have to be reachable too, not just the fields.
  final done = tester.getRect(find.text('Done'));
  expect(done.bottom, lessThanOrEqualTo(visibleBottom),
      reason: 'Done is under the keyboard');
}

void main() {
  testWidgets('a row near the bottom scrolls into view when tapped',
      (tester) async {
    await openCheck(tester);

    // The last line on this receipt, well below the fold.
    await tester.ensureVisible(find.text('Service charge 10%'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Service charge 10%'));
    await tester.pumpAndSettle();

    expectEditorUsable(tester, tester.view.physicalSize.height / 3.0);
  });

  testWidgets('it stays visible once the keyboard takes half the screen',
      (tester) async {
    await openCheck(tester);

    await tester.ensureVisible(find.text('Sparkling water'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sparkling water'));
    await tester.pumpAndSettle();

    // The keypad appears and eats the bottom of the viewport.
    tester.view.viewInsets = const FakeViewPadding(bottom: 800);
    await tester.pumpAndSettle();

    final visibleBottom =
        (tester.view.physicalSize.height - 800) / tester.view.devicePixelRatio;
    expectEditorUsable(tester, visibleBottom);
  });

  testWidgets('a newly added item opens ready to type', (tester) async {
    await openCheck(tester);

    await tester.ensureVisible(find.text('+ Add an item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Add an item'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Description'), findsOneWidget);
    expectEditorUsable(tester, tester.view.physicalSize.height / 3.0);
  });
}
