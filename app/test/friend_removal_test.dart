import 'package:bill/model/models.dart';
import 'package:bill/parsing/receipt.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

AppState withTwoFriends() {
  final app = AppState.ephemeral();
  app.friends = const [
    Friend(id: 'you', name: 'You', color: 0xFF1E2749),
    Friend(id: 'f1', name: 'Amara', color: 0xFF10A374),
  ];
  return app;
}

Receipt taxi({
  String paidBy = 'you',
  List<String> party = const ['you', 'f1'],
  Map<String, List<String>> assign = const {
    'l1': ['you', 'f1']
  },
}) =>
    Receipt(
      id: 'r1',
      name: 'Taxi',
      date: '1 Jan',
      paidBy: paidBy,
      party: party,
      lines: const [
        ReceiptLine(
            id: 'l1',
            description: 'Fare',
            amount: 20,
            kind: LineKind.item,
            rawText: 'FARE 20.00')
      ],
      assign: assign,
    );

void main() {
  test('someone with items on a bill cannot be removed', () {
    final app = withTwoFriends();
    app.groups = [Group(id: 'g', name: 'Trip', receipts: [taxi()])];

    app.removeFriend('f1');
    expect(app.friends.any((f) => f.id == 'f1'), isTrue);
    expect(app.toast, contains('still has items on Taxi'));
  });

  test('the person who paid cannot be removed, even claiming nothing', () {
    final app = withTwoFriends();
    app.groups = [
      Group(id: 'g', name: 'Trip', receipts: [
        taxi(paidBy: 'f1', assign: const {
          'l1': ['you']
        }),
      ])
    ];

    app.removeFriend('f1');
    expect(app.friends.any((f) => f.id == 'f1'), isTrue,
        reason: 'removing them would leave the receipt reading "Paid by ?"');
    expect(app.toast, contains('paid for Taxi'));
  });

  test('being on a bill without claiming anything still blocks removal', () {
    final app = withTwoFriends();
    app.groups = [
      Group(id: 'g', name: 'Trip', receipts: [
        taxi(assign: const {
          'l1': ['you']
        }),
      ])
    ];

    app.removeFriend('f1');
    expect(app.friends.any((f) => f.id == 'f1'), isTrue);
    expect(app.toast, contains('is on Taxi'));
  });

  test('someone who has settled up cannot be removed', () {
    final app = withTwoFriends();
    app.groups = [
      Group(
        id: 'g',
        name: 'Trip',
        receipts: const [],
        settlements: const [Settlement(from: 'f1', to: 'you', cents: 1000)],
      )
    ];

    app.removeFriend('f1');
    expect(app.friends.any((f) => f.id == 'f1'), isTrue);
    expect(app.toast, contains('settled up'));
  });

  test('someone on no bill at all can be removed', () {
    final app = withTwoFriends();
    app.groups = [
      Group(id: 'g', name: 'Trip', receipts: [
        taxi(party: const ['you'], assign: const {
          'l1': ['you']
        }),
      ])
    ];

    app.removeFriend('f1');
    expect(app.friends.any((f) => f.id == 'f1'), isFalse);
  });

  test('you can never remove yourself', () {
    final app = withTwoFriends();
    app.removeFriend('you');
    expect(app.friends.any((f) => f.id == 'you'), isTrue);
  });

  group('archived bills do not block a removal', () {
    AppState archivedTrip() {
      final app = withTwoFriends();
      app.groups = [
        Group(
          id: 'g',
          name: 'Trip',
          archived: true,
          receipts: [taxi()],
          settlements: const [Settlement(from: 'f1', to: 'you', cents: 1000)],
        )
      ];
      return app;
    }

    test('somebody who only appears in the archive can be removed', () {
      final app = archivedTrip();

      app.removeFriend('f1');

      expect(app.visibleFriends.any((f) => f.id == 'f1'), isFalse);
      expect(app.toast, isEmpty, reason: 'nothing to refuse');
    });

    test('the archive still knows their name', () {
      final app = archivedTrip();

      app.removeFriend('f1');

      expect(app.nameOf('f1'), 'Amara',
          reason: 'a closed book full of "?" is worse than no archive');
      expect(app.friendById('f1').removed, isTrue);
    });

    test('a live bill still blocks it, archive or no archive', () {
      final app = archivedTrip();
      app.groups = [
        ...app.groups,
        Group(id: 'live', name: 'Lisbon', receipts: [taxi()]),
      ];

      app.removeFriend('f1');

      expect(app.visibleFriends.any((f) => f.id == 'f1'), isTrue);
      expect(app.toast, contains('still has items on Taxi'));
    });

    test('the live group is the one named in the refusal', () {
      final app = withTwoFriends();
      app.groups = [
        Group(
          id: 'old',
          name: 'Trip',
          archived: true,
          receipts: const [],
          settlements: const [Settlement(from: 'f1', to: 'you', cents: 500)],
        ),
        Group(
          id: 'live',
          name: 'Lisbon',
          receipts: const [],
          settlements: const [Settlement(from: 'f1', to: 'you', cents: 500)],
        ),
      ];

      app.removeFriend('f1');
      expect(app.toast, contains('Lisbon'));
      expect(app.toast, isNot(contains('Trip')));
    });

    test('a draft blocks it even when every group is archived', () {
      final app = archivedTrip();
      app.startFlow();
      app.toggleParty('f1');

      app.removeFriend('f1');

      expect(app.visibleFriends.any((f) => f.id == 'f1'), isTrue);
      expect(app.toast, contains("Can't remove"));
    });

    test('restoring the group brings them back', () {
      final app = archivedTrip();
      app.removeFriend('f1');
      expect(app.visibleFriends.any((f) => f.id == 'f1'), isFalse);

      app.setArchived('g', false);

      expect(app.visibleFriends.any((f) => f.id == 'f1'), isTrue,
          reason: 'a live bill cannot credit somebody who does not exist');
      expect(app.friendById('f1').removed, isFalse);
    });

    test('the flag survives a save and a load', () async {
      var written = '';
      final app = AppState(
        loader: () async => written,
        saver: (json) async => written = json,
        quarantine: (_) async {},
        sweepQuarantinedAt: () async {},
        sweepPhotos: () async {},
        discardPhotoAt: (_) async {},
      );
      app.friends = const [
        Friend(id: 'you', name: 'You', color: 0xFF1E2749),
        Friend(id: 'f1', name: 'Amara', color: 0xFF10A374),
      ];
      app.groups = [
        Group(id: 'g', name: 'Trip', archived: true, receipts: [taxi()]),
      ];
      app.removeFriend('f1');
      await app.flushWrites();

      final reloaded = AppState(
        loader: () async => written,
        saver: (_) async {},
        quarantine: (_) async {},
        sweepQuarantinedAt: () async {},
        sweepPhotos: () async {},
        discardPhotoAt: (_) async {},
      );
      await reloaded.load();

      expect(reloaded.nameOf('f1'), 'Amara');
      expect(reloaded.visibleFriends.any((f) => f.id == 'f1'), isFalse);
    });
  });
}
