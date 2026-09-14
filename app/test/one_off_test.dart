import 'package:bill/model/models.dart';
import 'package:bill/parsing/receipt.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

AppState finishedOneOff() {
  final app = AppState.ephemeral();
  app.friends = const [
    Friend(id: 'you', name: 'You', color: 0xFF1E2749),
    Friend(id: 'f1', name: 'Amara', color: 0xFF10A374),
  ];
  app.startFlow();
  app.setDestination(null);
  app.toggleParty('f1');
  app.setBillName('Pizza night');
  app.setDraftLines(const [
    ReceiptLine(
        id: 'l1',
        description: 'Pizza',
        amount: 20,
        kind: LineKind.item,
        rawText: 'PIZZA 20.00'),
  ]);
  app.toggleAssign('l1', 'you');
  app.toggleAssign('l1', 'f1');
  app.finishFlow();
  return app;
}

void main() {
  test('a finished one-off split is visible on the home screen', () {
    final app = finishedOneOff();
    expect(app.groups.length, 1);
    expect(app.visibleGroups.length, 1,
        reason: 'it used to be saved and then shown nowhere');
    expect(app.visibleGroups.single.name, 'Pizza night');
  });

  test('it is not offered as somewhere to file the next bill', () {
    final app = finishedOneOff();
    expect(app.groupsForDestination, isEmpty,
        reason: 'a one-off is not a place to put a second receipt');
  });

  test('home shows what is still to settle on it', () {
    final app = finishedOneOff();
    // A twenty split two ways: Amara owes ten.
    expect(app.groupOutstandingCents(app.visibleGroups.single), 1000);
    expect(app.groupSpentCents(app.visibleGroups.single), 2000);
  });

  test('archiving one keeps it reachable', () {
    final app = finishedOneOff();
    app.setArchived(app.groups.single.id, true);
    expect(app.visibleGroups, isEmpty);
    expect(app.archivedGroups.length, 1,
        reason: 'archived one-offs used to vanish entirely');
  });
}
