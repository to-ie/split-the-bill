import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';
import 'package:bill/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Renaming a friend in Settings.
///
/// A name typed once, from memory, at a restaurant table is the thing most
/// likely to be wrong, and until now the only way to correct one was to
/// remove the person and add them again - which the app refuses the moment
/// they are on a bill, which is always.

/// Opens Settings with the semantics tree built, because these tests reach
/// for the rows the way a screen reader does - by the label they announce.
///
/// The handle has to be disposed inside the test body: the framework checks
/// for a stray one before tearDowns run, so addTearDown is too late.
Future<void> onSettings(
  WidgetTester tester,
  Future<void> Function(AppState app) body,
) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final semantics = tester.ensureSemantics();
  final state = populated();
  await tester.pumpWidget(BillApp(state: state));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();

  await body(state);
  semantics.dispose();
}

/// The one field open for renaming. Found by its hint rather than by
/// position: the screen has four text fields and which is last depends on
/// whether the PIN row is open.
final renameField = find.byWidgetPredicate(
  (w) => w is BillField && w.hint == 'Name',
);

/// The Friends card sits below the currencies, off the bottom of a phone.
Future<void> startRenaming(WidgetTester tester, String name) async {
  final target = find.text(name);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  group('the state', () {
    AppState withFriends() {
      final app = AppState.ephemeral();
      app.friends = demoFriends();
      app.groups = demoGroups();
      app.loaded = true;
      return app;
    }

    test('a renamed friend is renamed on the bills already filed', () {
      final app = withFriends();
      final lisbon = app.groupById('lisbon')!;
      expect(app.nameOf('f1'), 'Amara');

      app.renameFriend('f1', 'Amara Okafor');

      expect(app.nameOf('f1'), 'Amara Okafor');
      // Receipts hold ids, so the bills follow without being touched.
      expect(lisbon.receipts.any((r) => r.party.contains('f1')), isTrue);
      expect(
        app.totalsFor(app.groupById('lisbon')!).people
            .any((p) => p.friendId == 'f1'),
        isTrue,
      );
      expect(app.friendById('f1').name, 'Amara Okafor');
    });

    test('the colour and the id survive, so nothing else moves', () {
      final app = withFriends();
      final before = app.friendById('f1');

      app.renameFriend('f1', 'Ama');

      final after = app.friendById('f1');
      expect(after.id, before.id);
      expect(after.color, before.color);
    });

    test('a blank name is refused rather than stored', () {
      final app = withFriends();

      app.renameFriend('f1', '   ');

      expect(app.nameOf('f1'), 'Amara',
          reason: 'an empty field is a rename in progress, not an intention');
    });

    test('surrounding space is trimmed off', () {
      final app = withFriends();
      app.renameFriend('f1', '  Tomas  ');
      expect(app.friendById('f1').name, 'Tomas');
    });

    test('renaming you writes the one name in Settings, not a second copy',
        () {
      final app = withFriends();

      app.renameFriend('you', 'Sam');

      expect(app.settings.myName, 'Sam');
      expect(app.nameOf('you'), 'Sam');
    });

    test('renaming somebody who is gone changes nothing', () {
      final app = withFriends();
      final before = app.friends.length;

      app.renameFriend('nobody', 'Ghost');

      expect(app.friends.length, before);
      expect(app.friends.any((f) => f.name == 'Ghost'), isFalse);
    });

    test('the new name is written to the store', () async {
      var written = '';
      final app = AppState(
        loader: () async => null,
        saver: (json) async => written = json,
        quarantine: (_) async {},
        sweepQuarantinedAt: () async {},
        sweepPhotos: () async {},
        discardPhotoAt: (_) async {},
      );
      app.friends = demoFriends();

      app.renameFriend('f1', 'Amara Okafor');
      await app.flushWrites();

      expect(written, contains('Amara Okafor'));
    });
  });

  group('the screen', () {
    testWidgets('tapping a name opens it for editing and typing renames',
        (tester) async {
      await onSettings(tester, (app) async {
        await startRenaming(tester, 'Amara');

        await tester.enterText(renameField, 'Amara Okafor');
        await tester.pumpAndSettle();

        expect(app.nameOf('f1'), 'Amara Okafor');
      });
    });

    testWidgets('the tick closes the field and the new name is on the row',
        (tester) async {
      await onSettings(tester, (app) async {
        await startRenaming(tester, 'Tom');

        await tester.enterText(renameField, 'Tomas');
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Done renaming'));
        await tester.pumpAndSettle();

        expect(find.bySemanticsLabel('Done renaming'), findsNothing);
        expect(find.text('Tomas'), findsOneWidget);
        expect(find.bySemanticsLabel('Rename Tomas'), findsOneWidget);
      });
    });

    testWidgets('leaving the field empty leaves the name alone',
        (tester) async {
      await onSettings(tester, (app) async {
        await startRenaming(tester, 'Priya');

        await tester.enterText(renameField, '');
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Done renaming'));
        await tester.pumpAndSettle();

        expect(app.nameOf('f3'), 'Priya');
        expect(find.text('Priya'), findsOneWidget);
      });
    });

    testWidgets('your own row is named by the field at the top, not here',
        (tester) async {
      await onSettings(tester, (_) async {
        expect(find.bySemanticsLabel('Rename You'), findsNothing);
        expect(find.text('that is you'), findsOneWidget);
      });
    });

    testWidgets('a rename does not disturb the remove button beside it',
        (tester) async {
      await onSettings(tester, (app) async {
        await startRenaming(tester, 'Nadia');

        await tester.enterText(renameField, 'Nadia Rahman');
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Done renaming'));
        await tester.pumpAndSettle();

        // Nadia is on no bill, so she can still be removed - under the new
        // name, which is the one the button now offers to remove.
        final remove = find.bySemanticsLabel('Remove Nadia Rahman');
        await tester.ensureVisible(remove);
        await tester.pumpAndSettle();
        await tester.tap(remove);
        await tester.pumpAndSettle();

        expect(app.friends.any((f) => f.id == 'f4'), isFalse);
      });
    });
  });
}
