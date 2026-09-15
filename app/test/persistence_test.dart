import 'dart:convert';

import 'package:bill/logic/overpayment.dart';
import 'package:bill/logic/shares.dart';
import 'package:bill/model/models.dart';
import 'package:bill/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

/// Round-trips through the same JSON the device writes to disk. Every other
/// test keeps state in memory, which would not catch a field that never makes
/// it into the file.
Future<AppState> saveAndReload(AppState source) async {
  String? disk;
  final writer = AppState(
    loader: () async => null,
    saver: (json) async => disk = json,
  );
  writer.settings = source.settings;
  writer.friends = source.friends;
  writer.groups = source.groups;
  writer.setMyName(source.settings.myName); // forces a write
  await writer.flushWrites();

  final reloaded = AppState(
    loader: () async => disk,
    saver: (_) async {},
  );
  await reloaded.load();
  return reloaded;
}

void main() {
  test('a receipt survives being written to disk and read back', () async {
    final source = populated();
    final after = await saveAndReload(source);

    final before = source.groupById('lisbon')!.receipts
        .firstWhere((r) => r.id == 'live');
    final now = after.groupById('lisbon')!.receipts
        .firstWhere((r) => r.id == 'live');

    expect(now.name, before.name);
    expect(now.comment, before.comment);
    expect(now.date, before.date);
    expect(now.paidBy, before.paidBy);
    expect(now.party, before.party);
    expect(now.printedSubtotal, before.printedSubtotal);
    expect(now.printedTotal, before.printedTotal);
    expect(now.lines.length, before.lines.length);
    expect(now.grandCents, before.grandCents);
  });

  test('assignments survive, so the split is not silently lost', () async {
    final source = populated();
    final after = await saveAndReload(source);

    final before = source.groupById('lisbon')!.receipts
        .firstWhere((r) => r.id == 'live');
    final now = after.groupById('lisbon')!.receipts
        .firstWhere((r) => r.id == 'live');

    expect(now.assign, before.assign);
    expect(computeShares(now).per, computeShares(before).per);
  });

  test('line detail survives: kind, quantity, raw text, flags', () async {
    final source = populated();
    final after = await saveAndReload(source);

    final now = after.groupById('lisbon')!.receipts
        .firstWhere((r) => r.id == 'live');

    final peroni = now.lines.firstWhere((l) => l.id == 'i4');
    expect(peroni.quantity, 2);
    expect(peroni.rawText, '2 X PERONI 330ML 9.00');

    final service = now.lines.firstWhere((l) => l.id == 'a1');
    expect(service.kind.name, 'adjustment');

    final tiramisu = now.lines.firstWhere((l) => l.id == 'i5');
    expect(tiramisu.suspicious, isTrue);
  });

  test('settlements and group settings survive', () async {
    final source = populated();
    source.recordSettlement('lisbon', 'f2', 'you', 3092);
    source.setGroupCurrency('lisbon', '£');

    await source.flushWrites();
    final after = await saveAndReload(source);
    final g = after.groupById('lisbon')!;

    expect(g.settlements.length, 1);
    expect(g.settlements.single.from, 'f2');
    expect(g.settlements.single.cents, 3092);
    expect(g.currency, '£');
    expect(after.currencyFor('lisbon'), '£');
  });

  test('friends and settings survive', () async {
    final source = populated();
    source.setMyName('Theo');
    source.setDark(true);
    source.addCurrency('CHF');

    final after = await saveAndReload(source);

    expect(after.settings.myName, 'Theo');
    expect(after.settings.dark, isTrue);
    expect(after.settings.currencies, contains('CHF'));
    expect(after.friends.length, source.friends.length);
    expect(after.nameOf('f1'), 'Amara');
  });

  // ----------------------------------------- upgrading from an older app
  //
  // People upgrade. A store written before refunds existed, or before the
  // "settled" flag was replaced by real payments, still has to open - and
  // open with the same money in it.

  test('a store written before refunds existed still opens', () async {
    const old = '''
{
  "settings": {"myName": "Theo", "dark": false, "appCurrency": "E",
               "currencies": ["E"], "pinOn": false},
  "friends": [{"id": "you", "name": "You", "color": 1},
              {"id": "a", "name": "Ana", "color": 2}],
  "groups": [{
    "id": "g", "name": "Trip", "archived": false, "oneOff": false,
    "receipts": [{
      "id": "r1", "name": "Dinner", "comment": "", "date": "1 Jan",
      "paidBy": "you",
      "lines": [{"id": "l1", "description": "Meal", "amount": 30.0,
                 "kind": "item", "rawText": "Meal"}],
      "assign": {"l1": ["you", "a"]},
      "party": ["you", "a"]
    }],
    "settlements": [{"from": "a", "to": "you", "cents": 1500}]
  }]
}''';

    final app = AppState(
      loader: () async => old as String?,
      saver: (_) async {},
      quarantine: (_) async {},
      sweepQuarantinedAt: () async {},
      sweepPhotos: () async {},
      discardPhotoAt: (_) async {},
    );
    await app.load();

    expect(app.storeWasUnreadable, isFalse);
    final g = app.groupById('g')!;
    expect(g.settlements, hasLength(1));
    expect(g.settlements.single.refund, isFalse,
        reason: 'an old payment must not be mistaken for a refund');
    expect(g.settlements.single.cents, 1500);

    // And the money reads the same as it always did.
    final t = app.totalsFor(g);
    expect(t.allSquare, isTrue);
    expect(t.people.fold(0, (s, p) => s + p.netCents), 0);
    expect(overpaidBy(g), isEmpty);
  });

  test('a store still carrying the old settled flag is converted', () async {
    const old = '''
{
  "settings": {"myName": "", "dark": false, "appCurrency": "E",
               "currencies": ["E"], "pinOn": false},
  "friends": [{"id": "you", "name": "You", "color": 1},
              {"id": "a", "name": "Ana", "color": 2}],
  "groups": [{
    "id": "g", "name": "Trip", "archived": false, "oneOff": false,
    "receipts": [{
      "id": "r1", "name": "Dinner", "comment": "", "date": "1 Jan",
      "paidBy": "you", "settled": true,
      "lines": [{"id": "l1", "description": "Meal", "amount": 30.0,
                 "kind": "item", "rawText": "Meal"}],
      "assign": {"l1": ["you", "a"]},
      "party": ["you", "a"]
    }],
    "settlements": []
  }]
}''';

    final app = AppState(
      loader: () async => old as String?,
      saver: (_) async {},
      quarantine: (_) async {},
      sweepQuarantinedAt: () async {},
      sweepPhotos: () async {},
      discardPhotoAt: (_) async {},
    );
    await app.load();

    final g = app.groupById('g')!;
    // The flag became a real payment of what was outstanding.
    expect(g.settlements, hasLength(1));
    expect(g.settlements.single.from, 'a');
    expect(g.settlements.single.to, 'you');
    expect(g.settlements.single.cents, 1500);
    expect(g.settlements.single.refund, isFalse);
    expect(app.totalsFor(g).allSquare, isTrue);
  });

  test('the whole store is valid JSON with no surprises', () async {
    final source = populated();
    final encoded = jsonEncode(source.toJson());
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    expect(decoded.keys, containsAll(['settings', 'friends', 'groups']));
    expect(() => Group.fromJson((decoded['groups'] as List).first as Map<String, dynamic>),
        returnsNormally);
  });
}
