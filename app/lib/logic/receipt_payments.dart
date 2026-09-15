import '../model/models.dart';
import 'aggregate.dart';
import 'shares.dart';

enum PaymentProgress {
  /// Nobody who owes anything on this receipt has paid yet.
  none,

  /// Some of what is owed on this receipt has been paid.
  partial,

  /// Everyone who owed something on this receipt has paid it.
  full,
}

/// How far a single receipt has been paid off.
class ReceiptPayment {
  final String receiptId;

  /// What the people who are not the payer owe the payer for this receipt.
  final int owedCents;

  /// How much of [owedCents] is no longer outstanding, whether that is
  /// because somebody settled up or because the debt was cancelled out by a
  /// bill the same person fronted.
  final int paidCents;

  /// The part of [paidCents] that is money somebody actually handed over.
  ///
  /// The rest is offsetting: Ben owes fifty for dinner but put thirty on the
  /// taxi, so thirty of his dinner debt is gone without anybody paying
  /// anything. That is real arithmetic and it belongs in [paidCents], but it
  /// is not a payment, and a bill must not be badged "part paid" because of
  /// it - which is exactly what this app used to do.
  final int cashCents;

  /// Who has covered their share of this receipt in full.
  final Set<String> settledBy;

  /// Everyone who owes something on this receipt.
  final Set<String> debtors;

  /// What each debtor still owes on this receipt specifically.
  final Map<String, int> outstandingByPerson;

  /// Whether the whole group is square. When it is, there is nothing left to
  /// collect anywhere, so every bill in it is paid off by definition.
  final bool groupSquare;

  const ReceiptPayment({
    required this.receiptId,
    required this.owedCents,
    required this.paidCents,
    this.cashCents = 0,
    required this.settledBy,
    required this.debtors,
    this.outstandingByPerson = const {},
    this.groupSquare = false,
  });

  /// A receipt the payer covered alone has nothing to settle, and should not
  /// be badged as either paid or unpaid.
  bool get nothingToSettle => owedCents <= 0;

  /// A badge is a claim that money has moved, so it is only made when money
  /// has moved. The one exception is a group where everybody is square: then
  /// there is nothing left to collect on any bill in it, and saying so is
  /// true however the group got there.
  ///
  /// This is the fix for bills reading "Part paid" - and sometimes "Paid" -
  /// on a group where nobody had handed over a penny. Offsetting one person's
  /// dinner against the taxi they fronted really does cancel the debt, but it
  /// is not a payment, and badging it as one misreports the group.
  PaymentProgress get progress {
    if (nothingToSettle) return PaymentProgress.none;
    if (groupSquare) return PaymentProgress.full;
    if (paidCents <= 0 || cashCents <= 0) return PaymentProgress.none;
    if (paidCents >= owedCents) return PaymentProgress.full;
    return PaymentProgress.partial;
  }

  int get outstandingCents {
    final left = owedCents - paidCents;
    return left < 0 ? 0 : left;
  }
}

/// Works out, per receipt, how much of it has actually been paid back.
///
/// Settle-up clears *net* positions, not individual bills: one payment can
/// cover parts of three receipts, and somebody who paid for the taxi has that
/// set against what they owe for dinner. Matching payments against each
/// bill's gross debts therefore gets the wrong answer, because the payment is
/// smaller than the gross debt by whatever the payer is owed elsewhere.
///
/// So the question asked here is the one that actually matters: does this
/// person still owe the group anything? Whatever they owed that is no longer
/// outstanding is credited to their bills oldest first, which is the order
/// people assume debts are cleared in. When everybody is square, every bill
/// reads as paid.
///
/// That credit has two sources and they are counted separately, because they
/// mean different things to the people looking at the screen. Money handed
/// over is a payment. A debt cancelled by a bill the same person fronted is
/// not - nobody paid anything, the two amounts simply met in the middle. Only
/// the first can put a "part paid" badge on a bill.
///
/// This is presentation only. It deliberately does not mark receipts settled
/// or remove them from the group aggregation: the settlements have already
/// cancelled those debts in everyone's net, and excluding the receipt as well
/// would subtract the same money twice and break the invariant that the nets
/// sum to zero.
Map<String, ReceiptPayment> receiptPayments(Group group) {
  final totals = aggregate(group, (id) => id);
  final nets = {for (final p in totals.people) p.friendId: p.netCents};

  // What each person is out of pocket from settling up: what they handed over
  // to clear a debt, less everything that has come back to them.
  //
  // This used to be inferred by differencing the person's whole-group net
  // before and after the settlements. That reads the right number only while
  // they are still in debt: the moment a later bill put them in credit the
  // difference collapsed to zero, and a bill they had genuinely paid cash for
  // quietly stopped saying so. What somebody handed over is a fact about the
  // payments, not about where the group happens to stand afterwards.
  final handedOver = <String, int>{};
  for (final s in group.settlements) {
    handedOver[s.to] = (handedOver[s.to] ?? 0) - s.cents;
    if (!s.refund) {
      handedOver[s.from] = (handedOver[s.from] ?? 0) + s.cents;
    }
  }

  // Everything each person owes somebody else, in the order the bills were
  // added to the group.
  final debts = <String, List<(String, int)>>{};
  final owedPerReceipt = <String, int>{};
  final debtorsPerReceipt = <String, Set<String>>{};

  for (final receipt in group.receipts) {
    owedPerReceipt[receipt.id] = 0;
    debtorsPerReceipt[receipt.id] = <String>{};

    final shares = computeShares(receipt);
    for (final person in receipt.party) {
      if (person == receipt.paidBy) continue;
      final share = shares.per[person] ?? 0;
      // A negative share means this person is owed money on this bill, which
      // is not a debt to collect here.
      if (share <= 0) continue;

      (debts[person] ??= []).add((receipt.id, share));
      owedPerReceipt[receipt.id] = owedPerReceipt[receipt.id]! + share;
      debtorsPerReceipt[receipt.id]!.add(person);
    }
  }

  final paidPerReceipt = <String, int>{};
  final cashPerReceipt = <String, int>{};
  final settledPerReceipt = <String, Set<String>>{
    for (final r in group.receipts) r.id: <String>{},
  };
  final outstandingPerReceipt = <String, Map<String, int>>{
    for (final r in group.receipts) r.id: <String, int>{},
  };

  debts.forEach((person, owed) {
    final gross = owed.fold(0, (sum, d) => sum + d.$2);
    final owes = nets[person] ?? 0;

    // Everything of theirs that is no longer outstanding, however it got
    // that way.
    var credit = gross - (owes > 0 ? owes : 0);
    if (credit < 0) credit = 0;
    if (credit > gross) credit = gross;

    // Of that, the part they actually handed over. Capped at the credit,
    // because money paid beyond what they owed belongs to the overpayment
    // machinery, not to a badge on a bill.
    var cash = handedOver[person] ?? 0;
    if (cash < 0) cash = 0;
    if (cash > credit) cash = credit;

    // Both walk the bills oldest first, so the cash lands on the same bills
    // the credit cleared, earliest first.
    for (final (receiptId, share) in owed) {
      final applied = credit < share ? credit : share;
      credit -= applied;
      paidPerReceipt[receiptId] = (paidPerReceipt[receiptId] ?? 0) + applied;

      final paidInCash = cash < applied ? cash : applied;
      cash -= paidInCash;
      cashPerReceipt[receiptId] = (cashPerReceipt[receiptId] ?? 0) + paidInCash;

      if (applied >= share) {
        settledPerReceipt[receiptId]!.add(person);
      } else {
        outstandingPerReceipt[receiptId]![person] = share - applied;
      }
    }
  });

  return {
    for (final receipt in group.receipts)
      receipt.id: ReceiptPayment(
        receiptId: receipt.id,
        owedCents: owedPerReceipt[receipt.id] ?? 0,
        paidCents: paidPerReceipt[receipt.id] ?? 0,
        cashCents: cashPerReceipt[receipt.id] ?? 0,
        settledBy: settledPerReceipt[receipt.id] ?? const {},
        debtors: debtorsPerReceipt[receipt.id] ?? const {},
        outstandingByPerson: outstandingPerReceipt[receipt.id] ?? const {},
        groupSquare: totals.allSquare,
      ),
  };
}
