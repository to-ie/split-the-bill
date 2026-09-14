import 'dart:convert';

import 'package:bill/app.dart';
import 'package:bill/state/app_state.dart';
import 'package:bill/ui/widgets/privacy_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  group('the PIN is not kept in the clear', () {
    test('the stored file never contains the digits typed', () {
      final app = populated();
      app.setPin('4821');

      final written = jsonEncode(app.toJson());
      expect(written.contains('"4821"'), isFalse);
      expect(written.contains('"pin"'), isFalse);
      expect(app.settings.pinHash, isNotEmpty);
      expect(app.settings.pinSalt, isNotEmpty);
    });

    test('the right PIN verifies and the wrong one does not', () {
      final app = populated();
      app.setPin('4821');

      expect(app.verifyPin('4821'), isTrue);
      expect(app.verifyPin('4822'), isFalse);
      expect(app.verifyPin(''), isFalse);
      expect(app.verifyPin('48210'), isFalse);
    });

    test('two installs with the same PIN store different hashes', () {
      final a = populated()..setPin('1234');
      final b = populated()..setPin('1234');
      expect(a.settings.pinHash, isNot(b.settings.pinHash));
      expect(a.settings.pinSalt, isNot(b.settings.pinSalt));
    });

    test('with no PIN set, nothing verifies', () {
      final app = populated();
      expect(app.settings.hasPin, isFalse);
      expect(app.verifyPin('0000'), isFalse);
    });

    test('a plaintext PIN from an older build is converted on load', () async {
      // What version 0.7.0 and earlier wrote.
      final legacy = jsonEncode({
        'settings': {
          'myName': 'Theo',
          'dark': false,
          'appCurrency': '€',
          'currencies': ['€'],
          'pinOn': true,
          'pin': '9753',
        },
        'friends': [
          {'id': 'you', 'name': 'You', 'color': 0xFF1E2749}
        ],
        'groups': <dynamic>[],
      });

      String? disk = legacy;
      final app = AppState(
        loader: () async => disk,
        saver: (json) async => disk = json,
      );
      await app.load();

      expect(app.settings.hasPin, isTrue);
      expect(app.verifyPin('9753'), isTrue,
          reason: 'the old PIN still works after conversion');
      expect(disk!.contains('"9753"'), isFalse,
          reason: 'and the plaintext is gone from disk');
      expect(app.settings.pinOn, isTrue);
      expect(app.settings.myName, 'Theo');
    });
  });

  group('the app hides itself when it is not frontmost', () {
    Future<AppState> pump(WidgetTester tester, {required bool withPin}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      final state = populated();
      if (withPin) state.setPin('1234');
      await tester.pumpWidget(BillApp(state: state));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('a cover is drawn over the task switcher thumbnail',
        (tester) async {
      await pump(tester, withPin: true);

      // Unlock, so there is something worth hiding on screen.
      for (final d in '1234'.split('')) {
        await tester.tap(find.text(d));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Lisbon trip'), findsOneWidget);
      expect(find.byType(PrivacyCover), findsNothing);

      // Leaving the foreground is when the thumbnail is taken.
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(PrivacyCover), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyCover), findsNothing);
    });

    testWidgets('without a PIN there is no cover to flicker', (tester) async {
      await pump(tester, withPin: false);
      tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(PrivacyCover), findsNothing);
    });
  });

  group('the photo of the receipt does not outlive the scan', () {
    test('the working copy is deleted once the text has been read', () async {
      final discarded = <String>[];
      final app = AppState(
        loader: () async => null,
        saver: (_) async {},
        quarantine: (_) async {},
        sweepPhotos: () async {},
        discardPhotoAt: (path) async => discarded.add(path),
      );

      await app.discardScannedPhoto('/cache/receipt-1.jpg');
      expect(discarded, ['/cache/receipt-1.jpg']);
    });

    test('clearing all data sweeps the photos too', () async {
      var swept = false;
      final app = AppState(
        loader: () async => null,
        saver: (_) async {},
        quarantine: (_) async {},
        sweepPhotos: () async => swept = true,
        discardPhotoAt: (_) async {},
      );
      await app.load();

      app.clearAllData();
      expect(swept, isTrue,
          reason: 'wiping the receipts while keeping pictures of them '
              'would not be clearing all data');
      expect(app.groups, isEmpty);
      expect(app.friends.length, 1);
    });
  });

  group('nothing in the store is a surprise', () {
    test('the file holds only what the app is meant to keep', () {
      final app = populated();
      app.setPin('1234');
      final json = jsonDecode(jsonEncode(app.toJson())) as Map<String, dynamic>;

      expect(json.keys.toSet(), {'settings', 'friends', 'groups'});
      final settings = json['settings'] as Map<String, dynamic>;
      expect(
        settings.keys.toSet(),
        {
          'myName', 'dark', 'appCurrency', 'currencies',
          'pinOn', 'pinHash', 'pinSalt',
        },
        reason: 'no device id, no install id, no timestamps, no telemetry',
      );
    });
  });
}
