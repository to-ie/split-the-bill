import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppState> emptyGroup(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final state = AppState.ephemeral();
  await state.load();
  state.createGroup('Kithnos');
  await tester.pumpWidget(BillApp(state: state));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Kithnos'));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('a new group offers one way to start, not two', (tester) async {
    await emptyGroup(tester);

    expect(find.text('+ Add the first receipt'), findsOneWidget);
    expect(find.text('+ Add another receipt'), findsNothing);
    expect(find.textContaining('No receipts in this group'), findsNothing,
        reason: 'two dashed boxes stacked together read as one broken '
            'control');
  });

  testWidgets('it says where members come from', (tester) async {
    await emptyGroup(tester);
    expect(find.textContaining('Whoever has been on a receipt'), findsOneWidget);
  });

  testWidgets('once it has a receipt the wording changes', (tester) async {
    final state = await emptyGroup(tester);
    await tester.tap(find.text('+ Add the first receipt'));
    await tester.pumpAndSettle();
    expect(find.text("Who's splitting?"), findsOneWidget);
    expect(state.draft, isNotNull);
  });

  testWidgets('nothing overflows on an empty group', (tester) async {
    await emptyGroup(tester);
    expect(tester.takeException(), isNull);
  });
}
