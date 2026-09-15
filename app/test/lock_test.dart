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

/// The sequence Android really reports: resumed -> inactive -> paused on the
/// way out, and back through inactive on the way in.
Future<void> putDownAndPickUp(WidgetTester tester) async {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
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

  testWidgets('re-locking covers whatever screen was open', (tester) async {
    // The lock used to be expressed as MaterialApp's `home`, which is only the
    // bottom of the navigator stack. Anything pushed on top of it - a group,
    // a receipt, the summary with every figure on it - stayed on screen when
    // the app re-locked, so the PIN blocked the app only if you happened to
    // be on the home screen when you put the phone down.
    final state = await pumpLocked(tester);
    await enter(tester, '1234');
    expect(find.text('Split a new bill'), findsOneWidget);

    // Open a group, then the summary: two routes above the root.
    Future<void> open(String label) async {
      final f = find.text(label);
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    await open('Lisbon trip');
    await open('Group summary · who owes what overall');
    expect(find.text('Group summary'), findsOneWidget);

    // Put the phone down and pick it up again, through the states Android
    // actually reports.
    await putDownAndPickUp(tester);

    expect(find.text('Enter your PIN'), findsOneWidget);
    expect(find.text('Group summary'), findsNothing,
        reason: 'the summary was still readable through the lock');
    expect(find.textContaining('Lisbon'), findsNothing);
    expect(state.settings.pinOn, isTrue);
  });

  testWidgets('unlocking again puts you back where you were', (tester) async {
    await pumpLocked(tester);
    await enter(tester, '1234');
    final trip = find.text('Lisbon trip');
    await tester.ensureVisible(trip);
    await tester.pumpAndSettle();
    await tester.tap(trip);
    await tester.pumpAndSettle();

    await putDownAndPickUp(tester);
    expect(find.text('Enter your PIN'), findsOneWidget);

    await enter(tester, '1234');
    expect(find.text('Enter your PIN'), findsNothing);
    expect(find.textContaining('Lisbon'), findsWidgets);
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

  testWidgets('the keypad is reachable in landscape', (tester) async {
    // A phone on its side is about 360 points tall. The keypad is taller than
    // that, and it used to be clipped off the bottom - so a locked app could
    // not be opened at all without turning the phone back.
    tester.view.physicalSize = const Size(844 * 3, 390 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final state = populated();
    state.setPin('1234');
    await tester.pumpWidget(BillApp(state: state));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final d in '1234'.split('')) {
      final key = find.text(d);
      await tester.ensureVisible(key);
      await tester.pumpAndSettle();
      await tester.tap(key);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(find.text('Enter your PIN'), findsNothing,
        reason: 'the PIN could not be entered in landscape');
  });

  testWidgets('the keypad is reachable on a short screen at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 560 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final state = populated();
    state.setPin('1234');
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: BillApp(state: state),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    for (final d in '1234'.split('')) {
      final key = find.text(d);
      await tester.ensureVisible(key);
      await tester.pumpAndSettle();
      await tester.tap(key);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Enter your PIN'), findsNothing);
  });

  testWidgets('a PIN the keypad cannot type is refused', (tester) async {
    // The unlock keypad has only digits on it. A PIN with a letter in it -
    // pasted, or typed on a keyboard that ignores the numeric hint - could be
    // set and then never entered again, and with backups off that is the
    // receipts gone for good.
    final app = populated();
    app.setPin('ab12');
    expect(app.settings.hasPin, isFalse);
    expect(app.settings.pinHash, isEmpty);

    app.setPin('12');
    expect(app.settings.hasPin, isFalse);

    app.setPin('1234');
    expect(app.settings.hasPin, isTrue);
    expect(app.verifyPin('1234'), isTrue);
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
