import 'package:bill/app.dart';
import 'package:bill/theme/app_theme.dart';
import 'package:bill/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Tapping a coloured circle says whose it is.
///
/// A row of bare initials stops being readable the moment two people share a
/// first letter: Tom and Tara are the same circle, in an order nobody
/// memorised. The bubble is the answer, and on the screens where the circle
/// is also a control it has to appear without swallowing the tap.

Future<void> pumpAvatar(
  WidgetTester tester, {
  required String name,
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(false),
      home: Scaffold(
        body: Center(
          child: Avatar(name: name, color: const Color(0xFF10A374), onTap: onTap, revealName: true),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the name appears when the circle is tapped', (tester) async {
    await pumpAvatar(tester, name: 'Tara');
    expect(find.text('Tara'), findsNothing);

    await tester.tap(find.byType(Avatar));
    await tester.pumpAndSettle();

    expect(find.text('Tara'), findsOneWidget);
  });

  testWidgets('a circle that is also a control still does its job',
      (tester) async {
    var taps = 0;
    await pumpAvatar(tester, name: 'Tom', onTap: () => taps++);

    await tester.tap(find.byType(Avatar));
    await tester.pumpAndSettle();

    expect(taps, 1, reason: 'the tooltip must not swallow the tap');
    expect(find.text('Tom'), findsOneWidget);
  });

  testWidgets('the bubble goes away on its own', (tester) async {
    await pumpAvatar(tester, name: 'Tara');
    await tester.tap(find.byType(Avatar));
    await tester.pumpAndSettle();
    expect(find.text('Tara'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Tara'), findsNothing);
  });

  testWidgets('two people sharing a first letter can be told apart on assign',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final app = populated();
    // Priya becomes a second P, so the two circles are identical.
    app.renameFriend('f3', 'Pedro');
    await tester.pumpWidget(BillApp(state: app));
    await tester.pumpAndSettle();

    for (final step in [
      'Lisbon trip',
      'Trattoria Bella',
      'Edit this receipt',
      'Next · who had what?',
    ]) {
      final f = find.text(step);
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    // Both initials are on screen; neither name is.
    expect(find.text('Pedro'), findsNothing);

    final pedro =
        find.byWidgetPredicate((w) => w is Avatar && w.name == 'Pedro').first;
    await tester.ensureVisible(pedro);
    await tester.pumpAndSettle();
    await tester.tap(pedro);
    await tester.pumpAndSettle();

    expect(find.text('Pedro'), findsOneWidget);
  });
}
