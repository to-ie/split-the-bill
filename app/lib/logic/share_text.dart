import '../model/models.dart';
import '../model/money.dart';
import '../state/app_state.dart';
import 'shares.dart';

/// Plain-text summaries for the clipboard, LOGIC.md section 14.
/// No messaging SDKs: the user pastes this wherever they like.
const _footer = 'Shared from Split the Bill · receipts stay on the phone';

String shareReceiptText(AppState app, Receipt receipt, String currency) {
  final shares = computeShares(receipt);
  final b = StringBuffer();

  b.writeln('SPLIT THE BILL · ${receipt.name} · ${receipt.date}');
  b.writeln(
    'Total ${formatCents(receipt.grandCents, currency)} · ${receipt.party.length} people',
  );
  b.writeln('Paid by ${app.nameOf(receipt.paidBy)}');
  b.writeln();

  for (final who in receipt.party) {
    final total = shares.per[who] ?? 0;
    final verb = total < 0 ? app.getsVerb(who) : app.owesVerb(who);
    b.writeln('${app.nameOf(who)} $verb ${formatCents(total.abs(), currency)}');
    for (final line in shares.lines[who] ?? const <ShareLine>[]) {
      final div = line.splitBetween > 1 ? ' · ÷${line.splitBetween}' : '';
      b.writeln(
        '  · ${line.description}$div: ${formatCents(line.cents, currency)}',
      );
    }
  }

  b.writeln();
  b.write(_footer);
  return b.toString();
}

String shareGroupText(AppState app, Group group) {
  final currency = app.currencyFor(group.id);
  final totals = app.totalsFor(group);
  final b = StringBuffer();

  b.writeln(
    'SPLIT THE BILL · ${group.name} · '
    '${group.receipts.length} receipts',
  );
  b.writeln('Spent ${formatCents(totals.spentCents, currency)}');
  b.writeln(
    totals.outstandingCents == 0
        ? 'Everybody is square.'
        : 'Still to settle '
              '${formatCents(totals.outstandingCents, currency)}',
  );
  b.writeln();

  for (final p in totals.people) {
    final name = app.nameOf(p.friendId);
    final String headline;
    if (p.isSquare) {
      headline = '$name ${app.isYou(p.friendId) ? 'are' : 'is'} all square';
    } else if (p.owes) {
      headline =
          '$name ${app.owesVerb(p.friendId)} ${formatCents(p.netCents, currency)}';
    } else {
      headline =
          '$name ${app.getsVerb(p.friendId)} ${formatCents(-p.netCents, currency)}';
    }
    b.writeln(headline);
    for (final l in p.ledger) {
      b.writeln('  · ${l.label}: ${formatCents(l.cents, currency)}');
    }
  }

  if (totals.transfers.isNotEmpty) {
    b.writeln();
    b.writeln('Settle up:');
    for (final t in totals.transfers) {
      b.writeln(
        '  ${app.nameOf(t.from)} pays ${app.nameOf(t.to)}: ${formatCents(t.cents, currency)}',
      );
    }
  }

  b.writeln();
  b.write(_footer);
  return b.toString();
}
