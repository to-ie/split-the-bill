import 'package:bill/model/models.dart';
import 'package:bill/parsing/receipt.dart';
import 'package:bill/state/app_state.dart';

/// Demo content for tests and screenshots.
///
/// This used to be seeded into the app itself. It lives here now: the shipping
/// app starts empty, and only the tests need a populated world.
ReceiptLine item(String id, String desc, double amount,
        {LineKind kind = LineKind.item,
        int quantity = 1,
        bool suspicious = false,
        String? raw}) =>
    ReceiptLine(
      id: id,
      description: desc,
      amount: amount,
      quantity: quantity,
      kind: kind,
      rawText: raw ?? '${desc.toUpperCase()} ${amount.toStringAsFixed(2)}',
      suspicious: suspicious,
    );

const demoParty = ['you', 'f1', 'f2', 'f3'];

List<Friend> demoFriends() => const [
      Friend(id: 'you', name: 'You', color: 0xFF1E2749),
      Friend(id: 'f1', name: 'Amara', color: 0xFF10A374),
      Friend(id: 'f2', name: 'Tom', color: 0xFFE2A21B),
      Friend(id: 'f3', name: 'Priya', color: 0xFFD1603D),
      Friend(id: 'f4', name: 'Nadia', color: 0xFF4A6FD1),
    ];

/// The Trattoria Bella bill from the prototype, misread tiramisu included.
Receipt demoTrattoria() => Receipt(
      id: 'live',
      name: 'Trattoria Bella',
      comment: 'Dinner',
      date: '14 Sep 2026',
      paidBy: 'you',
      party: demoParty,
      printedSubtotal: 47.00,
      printedTotal: 51.70,
      lines: [
        item('i1', 'Burrata', 8.00),
        item('i2', 'Margherita', 9.50),
        item('i3', 'Diavola', 11.00),
        item('i4', 'Peroni 330ml', 9.00,
            quantity: 2, raw: '2 X PERONI 330ML 9.00'),
        item('i5', 'T1ramisu', 65.00,
            suspicious: true, raw: 'T1RAMISU 65.00'),
        item('i6', 'Sparkling water', 3.00),
        item('a1', 'Service charge 10%', 4.70,
            kind: LineKind.adjustment, raw: 'SERVICE 10% 4.70'),
      ],
      assign: const {
        'i1': ['you', 'f1'],
        'i2': ['f3'],
        'i3': ['f2'],
        'i4': ['f1', 'f2'],
        'i5': ['you'],
        'i6': demoParty,
        'a1': demoParty,
      },
    );

List<Group> demoGroups() => [
      Group(
        id: 'lisbon',
        name: 'Lisbon trip',
        receipts: [
          Receipt(
            id: 'r1',
            name: 'Museu do Azulejo',
            comment: 'Tickets',
            date: '12 Sep',
            paidBy: 'you',
            party: demoParty,
            lines: [item('t1', 'Tickets x4', 40.00)],
            assign: const {'t1': demoParty},
            printedTotal: 40.00,
          ),
          Receipt(
            id: 'r2',
            name: 'Gelato by the river',
            comment: 'Snack',
            date: '13 Sep',
            paidBy: 'f1',
            party: demoParty,
            lines: [item('t1', 'Gelato x4', 14.00)],
            assign: const {'t1': demoParty},
            printedTotal: 14.00,
          ),
          demoTrattoria(),
        ],
      ),
      Group(
        id: 'cr',
        name: 'Coffee run',
        receipts: [
          Receipt(
            id: 'r3',
            name: 'Coffee run',
            comment: 'Just you',
            date: 'yesterday',
            paidBy: 'you',
            party: const ['you'],
            lines: [item('t1', 'Flat white x2', 8.90)],
            assign: const {
              't1': ['you']
            },
            printedTotal: 8.90,
          ),
        ],
      ),
    ];

/// An AppState that persists nothing and holds the demo world.
AppState populated() {
  final app = AppState.ephemeral();
  app.friends = demoFriends();
  app.groups = demoGroups();
  app.loaded = true;
  return app;
}
