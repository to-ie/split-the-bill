import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../logic/aggregate.dart';
import '../logic/overpayment.dart';
import '../logic/receipt_payments.dart';
import '../model/models.dart';
import '../model/money.dart';
import '../parsing/receipt.dart';
import 'photo_cache.dart';
import 'store.dart';

/// Where a flow is heading. null groupId means a one-off split.
class Draft {
  final String? groupId;
  final Receipt receipt;
  final bool isNew;

  /// The receipt as it was when editing started, so discarding can put it
  /// back. Null for a bill being created.
  final Receipt? original;

  const Draft({
    required this.groupId,
    required this.receipt,
    this.isNew = true,
    this.original,
  });

  Draft copyWith({
    String? groupId,
    Receipt? receipt,
    bool clearGroup = false,
  }) => Draft(
    groupId: clearGroup ? null : (groupId ?? this.groupId),
    receipt: receipt ?? this.receipt,
    isNew: isNew,
    original: original,
  );
}

class AppState extends ChangeNotifier {
  /// Storage is injected so tests never touch the real filesystem, and so a
  /// platform that cannot supply a documents directory degrades to in-memory
  /// rather than hanging the app at startup.
  final Future<String?> Function() _load;
  final Future<void> Function(String) _write;

  final Future<void> Function(String) _quarantine;
  final Future<void> Function() _sweep;
  final Future<void> Function(String) _discardPhoto;

  AppState({
    Future<String?> Function()? loader,
    Future<void> Function(String)? saver,
    Future<void> Function(String)? quarantine,
    Future<void> Function()? sweepPhotos,
    Future<void> Function(String)? discardPhotoAt,
  }) : _load = loader ?? loadRaw,
       _write = saver ?? saveRaw,
       _quarantine = quarantine ?? saveCorrupt,
       _sweep = sweepPhotos ?? sweepPhotoCache,
       _discardPhoto = discardPhotoAt ?? discardPhoto;

  /// An AppState that keeps nothing, for tests and previews.
  factory AppState.ephemeral() => AppState(
    loader: () async => null,
    saver: (_) async {},
    quarantine: (_) async {},
    sweepPhotos: () async {},
    discardPhotoAt: (_) async {},
  );

  AppSettings settings = const AppSettings();
  List<Friend> friends = [];
  List<Group> groups = [];
  Draft? draft;

  String toast = '';
  bool loaded = false;

  /// Set when the store existed but could not be parsed. The unreadable file
  /// is kept alongside the new one rather than being overwritten.
  bool storeWasUnreadable = false;

  /// Cheap counter so screens can key off "something changed".
  int revision = 0;

  // ---------------------------------------------------------------- lookups

  Friend friendById(String id) => friends.firstWhere(
    (f) => f.id == id,
    // LOGIC.md section 11: historical receipts can reference a friend who
    // has since been deleted. Render them, do not crash.
    orElse: () => const Friend(id: '?', name: '?', color: 0xFF8B8677),
  );

  /// "You" is replaced by the name set in Settings, everywhere.
  String nameOf(String id) {
    final f = friendById(id);
    if (f.isYou) {
      return settings.myName.trim().isEmpty ? 'You' : settings.myName.trim();
    }
    return f.name;
  }

  bool isYou(String id) => id == 'you';

  /// Verb agreement: "You owe" but "Tom owes".
  String owesVerb(String id) => isYou(id) ? 'owe' : 'owes';
  String getsVerb(String id) => isYou(id) ? 'get back' : 'gets back';

  Group? groupById(String? id) {
    if (id == null) return null;
    for (final g in groups) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// Everything on the home screen, one-off splits included. They used to be
  /// filtered out here, which meant finishing a one-off split saved it and
  /// then showed it nowhere at all.
  List<Group> get visibleGroups => groups.where((g) => !g.archived).toList();

  List<Group> get archivedGroups => groups.where((g) => g.archived).toList();

  /// Where a new bill can be filed. A one-off is by definition not somewhere
  /// to put a second receipt, so it is not offered.
  List<Group> get groupsForDestination =>
      groups.where((g) => !g.archived && !g.oneOff).toList();

  String currencyFor(String? groupId) =>
      groupById(groupId)?.currency ?? settings.appCurrency;

  String money(double amount, {String? groupId}) =>
      formatMoney(amount, currencyFor(groupId));

  String moneyCents(int cents, {String? groupId}) =>
      formatCents(cents, currencyFor(groupId));

  // ----------------------------------------------------------------- toasts

  void showToast(String message) {
    toast = message;
    _bump();
  }

  void clearToast() {
    if (toast.isEmpty) return;
    toast = '';
    _bump();
  }

  void _bump() {
    revision++;
    notifyListeners();
  }

  /// Writes are queued rather than fired off in parallel. Two edits in quick
  /// succession each encode the whole store, and letting both run at once
  /// risks the older one landing last.
  Future<void> _writes = Future<void>.value();

  void _save() {
    _bump();
    final json = jsonEncode(toJson());
    _writes = _writes.then((_) => _write(json)).catchError((Object _) {});
  }

  /// For tests: waits until everything queued has been written.
  Future<void> flushWrites() => _writes;

  // --------------------------------------------------------------- settings

  void setMyName(String name) {
    settings = settings.copyWith(myName: name);
    _save();
  }

  void setDark(bool dark) {
    settings = settings.copyWith(dark: dark);
    _save();
  }

  void setPinOn(bool on) {
    settings = settings.copyWith(pinOn: on);
    _save();
  }

  /// Stores a salted hash of the PIN, never the PIN.
  void setPin(String pin) {
    final salt = _newSalt();
    settings = settings.copyWith(
      pinSalt: salt,
      pinHash: hashPin(pin, salt),
      pinOn: true,
    );
    _save();
  }

  bool verifyPin(String pin) {
    if (!settings.hasPin) return false;
    return hashPin(pin, settings.pinSalt) == settings.pinHash;
  }

  static String _newSalt() {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  void setAppCurrency(String symbol) {
    settings = settings.copyWith(appCurrency: symbol);
    _save();
  }

  void addCurrency(String symbol) {
    if (settings.currencies.contains(symbol)) return;
    settings = settings.copyWith(currencies: [...settings.currencies, symbol]);
    _save();
  }

  /// LOGIC.md section 10: two guards, both refusing with a toast.
  void removeCurrency(String symbol) {
    if (symbol == settings.appCurrency) {
      showToast('Set another currency as default first.');
      return;
    }
    for (final g in groups) {
      if (g.currency == symbol) {
        showToast('"${g.name}" still uses $symbol.');
        return;
      }
    }
    settings = settings.copyWith(
      currencies: settings.currencies.where((c) => c != symbol).toList(),
    );
    _save();
  }

  void setGroupCurrency(String groupId, String? symbol) {
    _updateGroup(
      groupId,
      (g) => symbol == null
          ? g.copyWith(clearCurrency: true)
          : g.copyWith(currency: symbol),
    );
  }

  // ---------------------------------------------------------------- friends

  Friend addFriend(String name) {
    final trimmed = name.trim();
    final id = 'f${DateTime.now().microsecondsSinceEpoch}';
    final friend = Friend(
      id: id,
      name: trimmed,
      color: friendPalette[friends.length % friendPalette.length],
    );
    friends = [...friends, friend];
    _save();
    return friend;
  }

  /// Refuses while any bill still refers to them.
  ///
  /// LOGIC.md section 4 only mentions assigned items, but paying for a bill
  /// and being on one are just as much a reference: deleting the person who
  /// paid left the receipt reading "Paid by ?" and the group crediting
  /// somebody who no longer existed.
  void removeFriend(String id) {
    if (id == 'you') return;

    final name = nameOf(id);
    String? blockedBy(Receipt r) {
      if (r.paidBy == id) return '$name paid for ${r.name}.';
      for (final ids in r.assign.values) {
        if (ids.contains(id)) return '$name still has items on ${r.name}.';
      }
      if (r.party.contains(id)) return '$name is on ${r.name}.';
      return null;
    }

    for (final g in groups) {
      for (final s in g.settlements) {
        if (s.from == id || s.to == id) {
          showToast("Can't remove $name. They have settled up in ${g.name}.");
          return;
        }
      }
      for (final r in g.receipts) {
        final reason = blockedBy(r);
        if (reason != null) {
          showToast("Can't remove $name. $reason");
          return;
        }
      }
    }

    final d = draft;
    if (d != null) {
      final reason = blockedBy(d.receipt);
      if (reason != null) {
        showToast("Can't remove $name. $reason");
        return;
      }
    }
    friends = friends.where((f) => f.id != id).toList();
    if (d != null && d.receipt.party.contains(id)) {
      _setDraftReceipt(
        d.receipt.copyWith(
          party: d.receipt.party.where((p) => p != id).toList(),
        ),
      );
    }
    _save();
  }

  // ----------------------------------------------------------------- groups

  Group createGroup(String name) {
    final g = Group(
      id: 'g${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'New group' : name.trim(),
      receipts: const [],
    );
    groups = [...groups, g];
    _save();
    return g;
  }

  void _updateGroup(String id, Group Function(Group) f) {
    groups = groups.map((g) => g.id == id ? f(g) : g).toList();
    _save();
  }

  void renameGroup(String id, String name) =>
      _updateGroup(id, (g) => g.copyWith(name: name));

  void setArchived(String id, bool archived) =>
      _updateGroup(id, (g) => g.copyWith(archived: archived));

  void deleteGroup(String id) {
    groups = groups.where((g) => g.id != id).toList();
    if (draft?.groupId == id) draft = null;
    _save();
  }

  // --------------------------------------------------------------- receipts

  /// Removes a bill.
  ///
  /// Payments already recorded stay exactly as they are - see
  /// [overpaidBy] for why - so deleting a bill somebody has settled leaves
  /// them holding money for a debt that has gone. Pass [refund] to give it
  /// back in the same action, which records the reverse payments rather than
  /// editing the originals.
  void deleteReceipt(String groupId, String receiptId, {bool refund = false}) {
    _updateGroup(groupId, (g) {
      final next = g.copyWith(
        receipts: g.receipts.where((r) => r.id != receiptId).toList(),
      );
      return refund ? withOverpaymentsRefunded(next) : next;
    });
  }

  /// What each person is holding that no longer answers to a debt.
  Map<String, int> overpaymentsIn(Group g) => overpaidBy(g);

  /// What deleting this bill would leave people holding, so the question can
  /// be put to the user while they still have the context to answer it.
  Map<String, int> creditIfReceiptDeleted(String groupId, String receiptId) {
    final g = groupById(groupId);
    if (g == null) return const {};
    return overpaymentIfDeleted(g, receiptId);
  }

  /// Gives one person back the money they are holding for nothing.
  void refundOverpayment(String groupId, String person) {
    final g = groupById(groupId);
    if (g == null) return;
    final refunds = refundsFor(g, person);
    if (refunds.isEmpty) return;
    _updateGroup(
      groupId,
      (g) => g.copyWith(settlements: [...g.settlements, ...refunds]),
    );
  }

  /// LOGIC.md section 8: mark a debt paid. The amount is frozen here on
  /// purpose, so later edits to the bills leave a residual rather than
  /// silently rewriting history.
  void recordSettlement(String groupId, String from, String to, int cents) {
    if (cents <= 0 || from == to) return;
    _updateGroup(
      groupId,
      (g) => g.copyWith(
        settlements: [
          ...g.settlements,
          Settlement(from: from, to: to, cents: cents),
        ],
      ),
    );
  }

  /// Removes the most recent payment recorded from [from] to [to].
  void undoSettlement(String groupId, String from, String to) {
    final g = groupById(groupId);
    if (g == null) return;
    final list = [...g.settlements];
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].from == from && list[i].to == to) {
        list.removeAt(i);
        break;
      }
    }
    _updateGroup(groupId, (g) => g.copyWith(settlements: list));
  }

  /// Removes one specific recorded payment, matching amount as well as the
  /// two people, so undoing one of several payments between the same pair
  /// takes back the one that was tapped.
  void undoSettlementRecord(String groupId, Settlement settlement) {
    final g = groupById(groupId);
    if (g == null) return;
    final list = [...g.settlements];
    for (var i = list.length - 1; i >= 0; i--) {
      if (list[i].from == settlement.from &&
          list[i].to == settlement.to &&
          list[i].cents == settlement.cents) {
        list.removeAt(i);
        break;
      }
    }
    _updateGroup(groupId, (g) => g.copyWith(settlements: list));
  }

  GroupTotals totalsFor(Group group) => aggregate(group, nameOf);

  /// What the group still has to hand over, after the payments recorded so
  /// far. Zero once everybody is square.
  int groupOutstandingCents(Group g) => totalsFor(g).outstandingCents;

  /// What the group has spent in total.
  int groupSpentCents(Group g) =>
      g.receipts.fold(0, (s, r) => s + r.grandCents);

  // ------------------------------------------------------------------ flows

  void startFlow() {
    draft = Draft(
      groupId: null,
      receipt: Receipt(
        id: 'r${DateTime.now().microsecondsSinceEpoch}',
        name: '',
        date: _today(),
        paidBy: 'you',
        lines: const [],
        assign: const {},
        party: const ['you'],
      ),
    );
    _bump();
  }

  void setDestination(String? groupId) {
    final d = draft;
    if (d == null) return;

    // Adding a receipt to an existing group starts with that group's people
    // already in the party. Making the user reselect the same four friends on
    // every receipt of a trip is the obvious thing to get wrong here.
    final group = groupById(groupId);
    final party = group == null || group.members.isEmpty
        ? d.receipt.party
        : <String>{'you', ...group.members}.toList();

    final receipt = d.receipt.copyWith(party: party);
    draft = groupId == null
        ? d.copyWith(clearGroup: true, receipt: receipt)
        : d.copyWith(groupId: groupId, receipt: receipt);
    _bump();
  }

  void _setDraftReceipt(Receipt r) {
    final d = draft;
    if (d == null) return;
    draft = d.copyWith(receipt: r);

    // A bill that already exists is saved as it is edited, not when the end
    // of the flow is reached. People open a receipt from the group summary to
    // assign a forgotten item and then press back, which is the natural thing
    // to do and used to throw the change away.
    if (!d.isNew && d.groupId != null) {
      _writeThrough(d.groupId!, r);
      return;
    }
    _bump();
  }

  void _writeThrough(String groupId, Receipt r) {
    final g = groupById(groupId);
    if (g == null || !g.receipts.any((x) => x.id == r.id)) {
      _bump();
      return;
    }
    _updateGroup(
      groupId,
      (g) => g.copyWith(
        receipts: g.receipts.map((x) => x.id == r.id ? r : x).toList(),
      ),
    );
  }

  void toggleParty(String friendId) {
    final d = draft;
    if (d == null || friendId == 'you') return;
    final party = [...d.receipt.party];
    if (party.contains(friendId)) {
      party.remove(friendId);
    } else {
      party.add(friendId);
    }
    _setDraftReceipt(d.receipt.copyWith(party: party));
  }

  void setDraftLines(List<ReceiptLine> lines) {
    final d = draft;
    if (d == null) return;
    _setDraftReceipt(d.receipt.copyWith(lines: lines));
  }

  void applyParse(ParsedReceipt parsed, {String? billName}) {
    final d = draft;
    if (d == null) return;
    _setDraftReceipt(
      d.receipt.copyWith(
        name: billName ?? d.receipt.name,
        lines: parsed.lines,
        printedSubtotal: parsed.subtotal,
        printedTotal: parsed.total,
      ),
    );
  }

  void updateLine(String lineId, ReceiptLine Function(ReceiptLine) f) {
    final d = draft;
    if (d == null) return;
    _setDraftReceipt(
      d.receipt.copyWith(
        lines: d.receipt.lines.map((l) => l.id == lineId ? f(l) : l).toList(),
      ),
    );
  }

  void deleteLine(String lineId) {
    final d = draft;
    if (d == null) return;
    final assign = {...d.receipt.assign}..remove(lineId);
    _setDraftReceipt(
      d.receipt.copyWith(
        lines: d.receipt.lines.where((l) => l.id != lineId).toList(),
        assign: assign,
      ),
    );
  }

  ReceiptLine addLine({LineKind kind = LineKind.item}) {
    final d = draft!;
    final line = ReceiptLine(
      id: 'c${DateTime.now().microsecondsSinceEpoch}',
      description: '',
      amount: null,
      kind: kind,
      rawText: 'added by hand',
      custom: true,
    );
    _setDraftReceipt(d.receipt.copyWith(lines: [...d.receipt.lines, line]));
    return line;
  }

  void setBillName(String name) =>
      _setDraftReceipt(draft!.receipt.copyWith(name: name));
  void setBillDate(String date) =>
      _setDraftReceipt(draft!.receipt.copyWith(date: date));
  void setBillComment(String comment) =>
      _setDraftReceipt(draft!.receipt.copyWith(comment: comment));
  void setPaidBy(String friendId) =>
      _setDraftReceipt(draft!.receipt.copyWith(paidBy: friendId));

  void toggleAssign(String lineId, String friendId) {
    final d = draft;
    if (d == null) return;
    final assign = {
      for (final e in d.receipt.assign.entries) e.key: [...e.value],
    };
    final list = assign[lineId] ??= [];
    if (list.contains(friendId)) {
      list.remove(friendId);
    } else {
      list.add(friendId);
    }
    _setDraftReceipt(d.receipt.copyWith(assign: assign));
  }

  /// LOGIC.md section 4: the same button clears when everything is assigned.
  bool get everythingAssignedToEveryone {
    final d = draft;
    if (d == null) return false;
    final rows = d.receipt.splitRows;
    if (rows.isEmpty) return false;
    return rows.every((r) {
      final a = d.receipt.assign[r.id] ?? const <String>[];
      return d.receipt.party.every(a.contains);
    });
  }

  void splitEquallyOrClear() {
    final d = draft;
    if (d == null) return;
    final clear = everythingAssignedToEveryone;
    final assign = <String, List<String>>{};
    for (final r in d.receipt.splitRows) {
      assign[r.id] = clear ? <String>[] : [...d.receipt.party];
    }
    _setDraftReceipt(d.receipt.copyWith(assign: assign));
  }

  /// Persist the draft into its group, creating a one-off group if needed.
  /// CORRECTION over the prototype: this is what makes a finished receipt a
  /// real, editable record rather than a frozen snapshot.
  String finishFlow() {
    final d = draft!;
    var groupId = d.groupId;

    if (groupId == null) {
      final g = Group(
        id: 'o${DateTime.now().microsecondsSinceEpoch}',
        name: d.receipt.name.isEmpty ? 'One-off split' : d.receipt.name,
        receipts: const [],
        oneOff: true,
      );
      groups = [...groups, g];
      groupId = g.id;
    }

    final g = groupById(groupId)!;
    final exists = g.receipts.any((r) => r.id == d.receipt.id);
    _updateGroup(
      groupId,
      (g) => g.copyWith(
        receipts: exists
            ? g.receipts
                  .map((r) => r.id == d.receipt.id ? d.receipt : r)
                  .toList()
            : [...g.receipts, d.receipt],
      ),
    );
    draft = null;
    _save();
    return groupId;
  }

  /// Open an existing receipt for editing. Every screen in the flow then
  /// works on it exactly as it does on a new one.
  void editReceipt(String groupId, String receiptId) {
    final g = groupById(groupId)!;
    final r = g.receipts.firstWhere((r) => r.id == receiptId);
    draft = Draft(groupId: groupId, receipt: r, isNew: false, original: r);
    _bump();
  }

  /// Steps out of an edit, keeping what was changed. The changes are already
  /// saved; this only closes the draft.
  void discardDraftKeepingChanges() {
    draft = null;
    _bump();
  }

  /// Abandons the draft. For a bill that already existed, that means putting
  /// it back as it was, because the edits have been saved as they were made.
  void discardDraft() {
    final d = draft;
    draft = null;
    if (d != null && !d.isNew && d.groupId != null && d.original != null) {
      _writeThrough(d.groupId!, d.original!);
      return;
    }
    _bump();
  }

  // ------------------------------------------------------------------- data

  /// Deletes the working copy of a scanned receipt once its text has been
  /// read. Injected so tests never touch the real filesystem.
  Future<void> discardScannedPhoto(String path) => _discardPhoto(path);

  void clearAllData() {
    settings = AppSettings(dark: settings.dark);
    friends = [const Friend(id: 'you', name: 'You', color: 0xFF1E2749)];
    groups = [];
    draft = null;
    _save();

    // The receipts are gone; the photographs of them have to go too, or
    // "clear all data" is not true.
    _sweep();
  }

  // ------------------------------------------------------- load / save JSON

  Map<String, dynamic> toJson() => {
    'settings': settings.toJson(),
    'friends': friends.map((f) => f.toJson()).toList(),
    'groups': groups.map((g) => g.toJson()).toList(),
  };

  /// Earlier builds had a "settled" flag on a receipt that cleared it by
  /// excluding it from the sums. The flag is gone, so a receipt that was
  /// settled under an older build would have its debts reappear. The payments
  /// that cleared it are written down once, on first load, and from then on
  /// there is only one way anything is paid off.
  void _migrateSettledReceipts(Map<String, dynamic> raw) {
    final settledIds = <String, Set<String>>{};
    for (final g in (raw['groups'] as List? ?? const [])) {
      final group = g as Map<String, dynamic>;
      final ids = <String>{};
      for (final r in (group['receipts'] as List? ?? const [])) {
        final receipt = r as Map<String, dynamic>;
        if (receipt['settled'] == true) ids.add(receipt['id'] as String);
      }
      if (ids.isNotEmpty) settledIds[group['id'] as String] = ids;
    }
    if (settledIds.isEmpty) return;

    groups = groups.map((group) {
      final ids = settledIds[group.id];
      if (ids == null) return group;

      // What each of those bills still owes, given whatever has been paid.
      final progress = receiptPayments(group);
      final added = <Settlement>[];
      for (final receipt in group.receipts) {
        if (!ids.contains(receipt.id)) continue;
        final owing =
            progress[receipt.id]?.outstandingByPerson ?? const <String, int>{};
        for (final entry in owing.entries) {
          if (entry.value <= 0) continue;
          added.add(
            Settlement(from: entry.key, to: receipt.paidBy, cents: entry.value),
          );
        }
      }
      if (added.isEmpty) return group;
      return group.copyWith(settlements: [...group.settlements, ...added]);
    }).toList();

    _write(jsonEncode(toJson()));
  }

  /// Salted SHA-256. See [AppSettings.pinHash] for what this does and does
  /// not protect against.
  static String hashPin(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> load() async {
    // A platform channel that never answers must not stop the app opening.
    final raw = await _load()
        .timeout(const Duration(seconds: 4), onTimeout: () => null)
        .catchError((Object _) => null);
    if (raw == null) {
      _seed();
    } else {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        settings = AppSettings.fromJson(j['settings'] as Map<String, dynamic>);
        friends = (j['friends'] as List)
            .map((e) => Friend.fromJson(e as Map<String, dynamic>))
            .toList();
        groups = (j['groups'] as List)
            .map((e) => Group.fromJson(e as Map<String, dynamic>))
            .toList();

        _migrateSettledReceipts(j);

        // Earlier builds kept the PIN in the clear. Convert it on first load
        // and write the file back without it.
        final legacy = (j['settings'] as Map<String, dynamic>)['pin'];
        if (legacy is String && legacy.isNotEmpty && !settings.hasPin) {
          final salt = _newSalt();
          settings = settings.copyWith(
            pinSalt: salt,
            pinHash: hashPin(legacy, salt),
          );
          _write(jsonEncode(toJson()));
        }
      } catch (_) {
        // The file is there but unreadable. Put it aside before anything
        // overwrites it, and say so rather than looking like a fresh install.
        await _quarantine(raw);
        _seed();
        storeWasUnreadable = true;
        showToast('Saved data could not be read. A copy has been kept.');
      }
    }
    loaded = true;
    _bump();

    // Anything a crash or a killed scan left behind. The photo is deleted as
    // soon as its text has been read, so in normal use this finds nothing.
    unawaited(_sweep());
  }

  static String _today() {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final n = DateTime.now();
    return '${n.day} ${months[n.month - 1]} ${n.year}';
  }

  /// First run. Just the user, no groups, no friends: the empty states on
  /// the home and group screens are the real starting point, not a fallback.
  void _seed() {
    friends = const [Friend(id: 'you', name: 'You', color: 0xFF1E2749)];
    groups = [];
  }
}
