import 'package:flutter/material.dart';

import '../../app.dart';
import '../../logic/receipt_payments.dart';
import '../../logic/shares.dart';
import '../../model/money.dart';
import '../../parsing/receipt.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/screen_scaffold.dart';
import 'check_screen.dart';
import 'summary_screen.dart' show CardLine, PersonCard;

/// A stored receipt, read only until "Edit this receipt" is tapped.
///
/// Unlike the prototype, which refused to reopen anything but the newest
/// receipt, editing loads any receipt back into the flow and writes it back
/// to the same id.
class ReceiptViewScreen extends StatelessWidget {
  final String groupId;
  final String receiptId;

  const ReceiptViewScreen({
    super.key,
    required this.groupId,
    required this.receiptId,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);
    final group = app.groupById(groupId);
    final receipt = group?.receipts.where((r) => r.id == receiptId).firstOrNull;
    if (receipt == null) return const SizedBox.shrink();

    final currency = app.currencyFor(groupId);
    final shares = computeShares(receipt);
    final payment = receiptPayments(group!)[receiptId];

    return ScreenScaffold(
      title: receipt.name,
      subtitle: 'Receipt · read only',
      bodyPadding: const EdgeInsets.fromLTRB(R.pad, 12, R.pad, 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(R.card),
              border: Border.all(color: c.line, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  receipt.name.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: mono(13, 700, color: c.ink, letterSpacing: 1),
                ),
                const SizedBox(height: 3),
                Text(
                  receipt.sub.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: mono(10.5, 400, color: c.muted),
                ),
                const DashedRule(margin: EdgeInsets.fromLTRB(0, 12, 0, 4)),
                for (final l in receipt.splitRows)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            l.description.isEmpty
                                ? '(no description)'
                                : l.description,
                            style: mono(13, 500, color: c.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          formatMoney(l.effective, currency),
                          style: mono(
                            13,
                            700,
                            color: l.kind == LineKind.discount ? c.okFg : c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                const DashedRule(margin: EdgeInsets.fromLTRB(0, 6, 0, 10)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: CompactRow(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TOTAL', style: mono(13.5, 700, color: c.ink)),
                        Text(
                          formatCents(receipt.grandCents, currency),
                          style: mono(13.5, 700, color: c.ink),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('PAID BY', style: mono(11, 400, color: c.muted)),
                      Flexible(
                        child: Text(
                          app.nameOf(receipt.paidBy).toUpperCase(),
                          style: mono(11, 400, color: c.muted),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (payment != null && payment.progress != PaymentProgress.none) ...[
            const SizedBox(height: R.gap),
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: payment.progress == PaymentProgress.full
                    ? c.okBg
                    : c.amberBg,
                borderRadius: BorderRadius.circular(R.input),
              ),
              child: Text(
                payment.progress == PaymentProgress.full
                    ? 'Paid up · everyone has settled their share'
                    : '${payment.settledBy.length} of '
                          '${payment.debtors.length} have settled their share',
                style: ui(
                  12.5,
                  800,
                  color: payment.progress == PaymentProgress.full
                      ? c.okFg
                      : Brand.amberIcon,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          const SectionLabel('Each person'),
          const SizedBox(height: 10),
          for (final id in receipt.party) ...[
            PersonCard(
              name: app.nameOf(id),
              color: Color(app.friendById(id).color),
              amount: formatCents(shares.per[id] ?? 0, currency),
              lines: [
                for (final l in shares.lines[id] ?? const <ShareLine>[])
                  CardLine(
                    l.splitBetween > 1
                        ? '${l.description} · ÷${l.splitBetween}'
                        : l.description,
                    formatCents(l.cents, currency),
                  ),
              ],
            ),
            const SizedBox(height: R.gap),
          ],
        ],
      ),
      // Sharing lives on the group summary, which is the thing worth sending.
      // A single receipt out of context told people less than the group total
      // did and read as a second, competing way to do the same job.
      footer: ChipButton(
        label: 'Edit this receipt',
        onPressed: () {
          app.editReceipt(groupId, receiptId);
          Navigator.of(context).push(fadeUpRoute(const CheckScreen()));
        },
      ),
    );
  }
}
