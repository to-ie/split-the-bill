/// Fewest-payments settle-up, LOGIC.md section 8.
library;

class Transfer {
  final String from;
  final String to;
  final int cents;
  const Transfer({required this.from, required this.to, required this.cents});
}

/// Greedily match the largest debtor against the largest creditor.
///
/// Produces at most (debtors + creditors - 1) transfers, because every step
/// zeroes at least one person. This is not guaranteed to be the theoretical
/// minimum number of payments - that problem is NP-hard - but it is what the
/// design specifies and it is optimal whenever no subset of people happens to
/// net to zero among themselves.
///
/// Works in integer cents, so the transfers sum exactly to the debts.
List<Transfer> settleUp(Map<String, int> nets) {
  // net > 0 means this person owes.
  final debtors = <MapEntry<String, int>>[];
  final creditors = <MapEntry<String, int>>[];

  for (final e in nets.entries) {
    if (e.value > 0) {
      debtors.add(MapEntry(e.key, e.value));
    } else if (e.value < 0) {
      creditors.add(MapEntry(e.key, -e.value));
    }
  }

  // Descending by magnitude, with the id as a tie-break so that two people
  // owing the same amount produce a stable order rather than a list that
  // reshuffles every rebuild.
  int byMagnitude(MapEntry<String, int> a, MapEntry<String, int> b) {
    final c = b.value.compareTo(a.value);
    return c != 0 ? c : a.key.compareTo(b.key);
  }

  debtors.sort(byMagnitude);
  creditors.sort(byMagnitude);

  final transfers = <Transfer>[];
  var i = 0;
  var j = 0;
  var debtLeft = debtors.isEmpty ? 0 : debtors[0].value;
  var creditLeft = creditors.isEmpty ? 0 : creditors[0].value;

  while (i < debtors.length && j < creditors.length) {
    final pay = debtLeft < creditLeft ? debtLeft : creditLeft;

    if (pay > 0) {
      transfers.add(
        Transfer(from: debtors[i].key, to: creditors[j].key, cents: pay),
      );
    }

    debtLeft -= pay;
    creditLeft -= pay;

    // Advance whichever side is now clear. Half a penny cannot exist in
    // integer cents, so the test is simply zero.
    if (debtLeft == 0) {
      i++;
      if (i < debtors.length) debtLeft = debtors[i].value;
    }
    if (creditLeft == 0) {
      j++;
      if (j < creditors.length) creditLeft = creditors[j].value;
    }
  }

  return transfers;
}
