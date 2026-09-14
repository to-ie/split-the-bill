import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

Future<AppState> pumpLocked(WidgetTester tester, {String pin = '1234'}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final state = populated();
  state.setPin(pin);
  await tester.pumpWidget(BillApp(state: state));
  await tester.pumpAndSettle();
  return state;
}

Future<void> enter(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.text(d));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a set PIN blocks the app at launch', (tester) async {
    await pumpLocked(tester);
    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.text('Split a new bill'), findsNothing);
    expect(find.text('Lisbon trip'), findsNothing);
  });

  testWidgets('the wrong PIN does not let you in', (tester) async {
    await pumpLocked(tester);
    await enter(tester, '9999');
    expect(find.text('Wrong PIN'), findsOneWidget);
    expect(find.text('Split a new bill'), findsNothing);
  });

  testWidgets('the right PIN opens the app', (tester) async {
    await pumpLocked(tester);
    await enter(tester, '1234');
    expect(find.text('Split a new bill'), findsOneWidget);
    expect(find.text('Enter your PIN'), findsNothing);
  });

  testWidgets('backspace clears a digit', (tester) async {
    await pumpLocked(tester);
    await enter(tester, '12');
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pumpAndSettle();
    await enter(tester, '234');
    // 1 -> 2 -> back -> 2,3,4 gives 1234.
    expect(find.text('Split a new bill'), findsOneWidget);
  });

  testWidgets('leaving the app re-locks it', (tester) async {
    await pumpLocked(tester);
    await enter(tester, '1234');
    expect(find.text('Split a new bill'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Enter your PIN'), findsOneWidget);
  });

  testWidgets('no PIN set means no lock screen', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final state = populated();
    await tester.pumpWidget(BillApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsNothing);
    expect(find.text('Split a new bill'), findsOneWidget);
  });
}
