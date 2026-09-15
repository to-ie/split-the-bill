import 'package:bill/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Walks the whole app at sizes and text scales people actually use, and
/// fails on any overflow. A layout that only works at one width is not
/// finished.
Future<void> walk(
  WidgetTester tester, {
  required Size size,
  required double textScale,
  bool dark = false,
  bool archive = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final state = populated();
  if (dark) state.setDark(true);

  // The archive link on the home screen only exists when something has been
  // archived, so without this no size or text scale ever laid it out - which
  // is how it came to overflow a small phone at large text unnoticed.
  if (archive) {
    state.groups = [
      state.groups.first,
      for (final g in state.groups.skip(1)) g.copyWith(archived: true),
    ];
  }

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: BillApp(state: state),
    ),
  );
  await tester.pumpAndSettle();

  Future<void> tap(String text) async {
    final f = find.text(text);
    if (f.evaluate().isEmpty) return;
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> back() async {
    final f = find.bySemanticsLabel('Back');
    if (f.evaluate().isEmpty) return;
    await tester.tap(f.first);
    await tester.pumpAndSettle();
  }

  // Home, settings, and back.
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
  await back();

  if (archive) {
    await tap('Archived groups (1)');
    await back();
  }

  // A group, its receipts, and the summary.
  await tap('Lisbon trip');
  await tap('Group summary · who owes what overall');
  await back();
  await tap('Trattoria Bella');
  await tap('Edit this receipt');
  await tap('Burrata');            // the inline editor
  await tap('Done');
  await tap('Next · who had what?');
  await tap('Split equally');
  await tap('See the summary');
  await tap('Done');

  // And the whole new-bill flow.
  await tap('Split a new bill');
  await tap('One-off split');
  await tap('Amara');
  await tap('Next · scan the bill');
  await tap('Gallery');
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  await tap('Next · who had what?');
  await tap('See the summary');
}

void main() {
  final sizes = <String, Size>{
    'a small phone (320)': Size(320, 640),
    'a normal phone (390)': Size(390, 844),
    'a large phone (430)': Size(430, 932),
    // Capped sizes a control against the screen, and the home row leaves a
    // fixed 206 points for the name. Neither may bite where there is room.
    'a small tablet (600)': Size(600, 960),
    'a tablet (834)': Size(834, 1112),
    'a foldable open (1100)': Size(1100, 1000),
  };

  sizes.forEach((label, size) {
    testWidgets('no overflow on $label', (tester) async {
      await walk(tester, size: size, textScale: 1.0);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('no overflow with larger text (1.3x)', (tester) async {
    await walk(tester, size: const Size(390, 844), textScale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow with much larger text (1.6x)', (tester) async {
    await walk(tester, size: const Size(390, 844), textScale: 1.6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow in dark mode', (tester) async {
    await walk(tester, size: const Size(390, 844), textScale: 1.0, dark: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow with an archive on a small phone', (tester) async {
    await walk(tester,
        size: const Size(320, 640), textScale: 1.0, archive: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow with an archive at 1.6x text', (tester) async {
    await walk(tester,
        size: const Size(360, 640), textScale: 1.6, archive: true);
    expect(tester.takeException(), isNull);
  });

  // The worst case anyone can actually configure: the narrowest phone still
  // sold, with the largest text Android offers.
  testWidgets('a tablet at large text', (tester) async {
    await walk(tester, size: const Size(834, 1112), textScale: 1.6,
        archive: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at 320 wide and 1.6x text', (tester) async {
    await walk(tester,
        size: const Size(320, 640), textScale: 1.6, archive: true);
    expect(tester.takeException(), isNull);
  });

  // The strip that appears when a settled bill has been deleted is the
  // wordiest thing in the app and carries a button beside it.
  testWidgets('no overflow on a group holding money for a deleted bill',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = populated();
    for (final t in state.totalsFor(state.groupById('lisbon')!).transfers) {
      state.recordSettlement('lisbon', t.from, t.to, t.cents);
    }
    state.deleteReceipt('lisbon', 'r1');

    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
      child: BillApp(state: state),
    ));
    await tester.pumpAndSettle();

    Future<void> open(String label) async {
      final f = find.text(label);
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    await open('Lisbon trip');
    await open('Group summary · who owes what overall');

    final strip = find.textContaining('no longer here');
    expect(strip, findsWidgets);
    await tester.ensureVisible(strip.first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
