import 'package:bill/app.dart';
import 'package:bill/model/models.dart';
import 'package:bill/state/app_state.dart';
import 'package:bill/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// "Split a new bill" is the only reason anyone opens this app. It used to be
/// the last thing in one long scrolling column, so a third group and an
/// archive row pushed it off the bottom of the screen and the app looked as
/// though it could not do anything.
AppState withGroups(int count, {bool archived = false}) {
  final app = populated();
  final base = app.groups.first;
  app.groups = [
    for (var i = 0; i < count; i++)
      Group(
        id: 'g$i',
        name: 'Group number $i',
        receipts: base.receipts,
      ),
    if (archived)
      Group(id: 'old', name: 'Last year', archived: true, receipts: const []),
  ];
  return app;
}

/// Logical sizes, as the layout sees them. A phone reports around 390x844;
/// a small or older one around 360x640. Testing at physical pixels with a
/// device pixel ratio of one gives a screen a thousand points tall, which
/// nothing ever falls off the bottom of.
const phone = Size(390, 844);
const smallPhone = Size(360, 640);

Future<void> openHome(WidgetTester tester, AppState app, Size size,
    {double textScale = 1.0}) async {
  const dpr = 3.0;
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: BillApp(state: app),
  ));
  await tester.pumpAndSettle();
}

/// Is the button entirely inside the screen, without anyone scrolling?
void expectCallToActionVisible(WidgetTester tester, String why) {
  final button = find.widgetWithText(PrimaryButton, 'Split a new bill');
  expect(button, findsOneWidget, reason: why);

  final box = tester.getRect(button);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

  expect(box.bottom, lessThanOrEqualTo(screen.height),
      reason: 'the button runs off the bottom $why');
  expect(box.top, greaterThanOrEqualTo(0.0),
      reason: 'the button is above the top of the screen $why');
  expect(box.height, greaterThan(0.0), reason: 'the button collapsed $why');
}

void main() {
  testWidgets('the call to action stays on screen with three groups '
      'and an archive', (tester) async {
    await openHome(tester, withGroups(3, archived: true), phone);
    expect(find.text('Archived groups (1)'), findsOneWidget);
    expectCallToActionVisible(tester, 'with three groups and an archive');
  });

  testWidgets('and with far more groups than fit', (tester) async {
    await openHome(tester, withGroups(12, archived: true), phone);
    expectCallToActionVisible(tester, 'with twelve groups');
  });

  testWidgets('and on a short screen at large text', (tester) async {
    await openHome(tester, withGroups(3, archived: true), smallPhone,
        textScale: 1.6);
    expectCallToActionVisible(tester, 'on a small screen at 1.6x text');
  });

  testWidgets('and with nothing in it at all', (tester) async {
    final app = AppState.ephemeral();
    await app.load();
    await openHome(tester, app, phone);
    expectCallToActionVisible(tester, 'on an empty home screen');
  });

  testWidgets('the groups still scroll behind it', (tester) async {
    await openHome(tester, withGroups(12, archived: true), phone);

    // The last group is off screen to begin with, and scrolling reaches it
    // without the button moving.
    final button = tester.getRect(
        find.widgetWithText(PrimaryButton, 'Split a new bill'));

    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(
          find.widgetWithText(PrimaryButton, 'Split a new bill')),
      button,
      reason: 'the button must not move when the list scrolls',
    );
    expectCallToActionVisible(tester, 'after scrolling');
  });
}
