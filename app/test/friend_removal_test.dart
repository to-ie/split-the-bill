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
}
