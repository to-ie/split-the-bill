import 'package:flutter/material.dart';

import '../../app.dart';
import '../../logic/share_text.dart';
import '../../model/models.dart';
import '../../model/money.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/screen_scaffold.dart';
import '../widgets/share_sheet.dart';
import 'assign_screen.dart';
import 'summary_screen.dart';

class GroupSummaryScreen extends StatelessWidget {
  final String groupId;
  const GroupSummaryScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);
    final g = app.groupById(groupId);
    if (g == null) return const SizedBox.shrink();

    final currency = app.currencyFor(groupId);
    final totals = app.totalsFor(g);
    final n = g.receipts.length;

    // What anyone is holding that no longer answers to a debt, because a bill
    // they had settled was later deleted or edited down.
    final overpaid = app.overpaymentsIn(g);

    // Money on a bill that belongs to nobody yet makes every figure below it
    // an underestimate.
    final incomplete = totals.unassigned.isNotEmpty;

    return ScreenScaffold(
      title: 'Group summary',
      subtitle: 'Every receipt, one total each',
      bodyPadding: const EdgeInsets.fromLTRB(R.pad, 10, R.pad, 0),
      actions: [
        RoundIconButton(
          semanticLabel: 'Home',
          onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
          icon: Icon(Icons.home_outlined, size: 19, color: c.muted),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeroPanel(
            title: g.name,
            subtitle:
                '$n ${n == 1 ? 'receipt' : 'receipts'} · '
                '${formatCents(totals.spentCents, currency)} spent',
            amount: totals.outstandingCents == 0
                ? 'All square'
                : formatCents(totals.outstandingCents, currency),
            label: totals.outstandingCents == 0 ? null : 'still to settle',
          ),

          // Explains the gap between the hero total and the person cards.
          for (final (receipt, cents) in totals.unassigned) ...[
            const SizedBox(height: R.gap),
            AmberBanner(
              text:
                  '${formatCents(cents, currency)} on ${receipt.name} '
                  'is not assigned to anyone yet.',
              onTap: () {
                app.editReceipt(groupId, receipt.id);
                Navigator.of(context).push(fadeUpRoute(const AssignScreen()));
              },
            ),
          ],

          if (totals.transfers.isNotEmpty) ...[
            const SizedBox(height: R.gap),
            BillCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'SETTLE UP · FEWEST PAYMENTS',
                    style: ui(11.5, 900, color: c.muted, letterSpacing: 0.7),
                  ),
                  const SizedBox(height: 9),
                  for (final t in totals.transfers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _TransferRow(
                        groupId: groupId,
                        from: t.from,
                        to: t.to,
                        cents: t.cents,
                        currency: currency,
                        // Settling up while money on a bill belongs to
                        // nobody would record payments against figures that
                        // are known to be wrong, and the shortfall reappears
                        // the moment the item is assigned.
                        blocked: incomplete,
                      ),
                    ),
                  Note(
                    incomplete
                        ? 'Finish assigning the items above before settling '
                              'up: these figures are short until you do.'
                        : 'Tap a circle to see who it is. Marking a payment '
                              "as paid records it and updates everyone's "
                              'balance.',
                    fontSize: 11,
                  ),
                ],
              ),
            ),
          ],

          // Recorded payments, with a way back out of each one. A settle-up
          // tap is easy to make by accident and, being frozen at the amount
          // it was made, impossible to unpick by hand afterwards.
          if (g.settlements.isNotEmpty) ...[
            const SizedBox(height: R.gap),
            BillCard(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'PAYMENTS RECORDED',
                    style: ui(11.5, 900, color: c.muted, letterSpacing: 0.7),
                  ),
                  const SizedBox(height: 9),
                  for (var i = 0; i < g.settlements.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: _RecordedRow(
                        groupId: groupId,
                        settlement: g.settlements[i],
                        currency: currency,
                      ),
                    ),
                  const Note(
                    'Undo puts the debt back exactly as it was.',
                    fontSize: 11,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          if (totals.people.isEmpty || totals.allSquare)
            DashedBox(
              child: Text(
                'All bills are marked as paid up. Nothing owed.',
                textAlign: TextAlign.center,
                style: ui(13.5, 700, color: c.muted),
              ),
            )
          else ...[
            const Note(
              'Each bill below is broken down into what that person actually '
              'had. Nobody is charged a share of what somebody else ordered.',
              fontSize: 11.5,
            ),
            const SizedBox(height: 10),
            for (final p in totals.people) ...[
              PersonCard(
                name: app.nameOf(p.friendId),
                color: Color(app.friendById(p.friendId).color),
                // Zero, not a dash: it is a real figure and it says the
                // same thing more plainly.
                amount: formatCents(p.netCents.abs(), currency),
                amountColor: p.getsBack ? c.okFg : c.ink,
                status: p.isSquare
                    ? 'all square'
                    : p.owes
                    ? app.owesVerb(p.friendId)
                    : app.getsVerb(p.friendId),
                lines: [
                  for (final l in p.ledger)
                    CardLine(
                      l.label,
                      formatCents(l.cents, currency),
                      color: l.cents < 0 ? c.okFg : null,
                      detail: [
                        for (final d in l.detail)
                          CardLine(d.label, formatCents(d.cents, currency)),
                      ],
                    ),
                ],
                footer: (overpaid[p.friendId] ?? 0) > 0
                    ? _OverpaidRow(
                        groupId: groupId,
                        person: p.friendId,
                        cents: overpaid[p.friendId]!,
                        currency: currency,
                      )
                    : null,
              ),
              const SizedBox(height: R.gap),
            ],
          ],
        ],
      ),
      footer: PrimaryButton(
        label: 'Share the group total',
        onPressed: () => showShareSheet(
          context,
          'Send the group total',
          shareGroupText(app, g),
        ),
      ),
    );
  }
}

class _TransferRow extends StatelessWidget {
  final String groupId;
  final String from;
  final String to;
  final int cents;
  final String currency;

  /// True while something on a bill is still unassigned, in which case this
  /// amount is not yet the real one.
  final bool blocked;

  const _TransferRow({
    required this.groupId,
    required this.from,
    required this.to,
    required this.cents,
    required this.currency,
    this.blocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);

    // Two names, an amount and a button will not fit on one phone-width line
    // without wrapping or truncating, and a wrapped name reads as a mistake.
    // The avatars already carry the who; the amount is what people came here
    // to read. Names are a tap away on the circles.
    return Semantics(
      label:
          '${app.nameOf(from)} pays ${app.nameOf(to)} '
          '${formatCents(cents, currency)}',
      child: CompactRow(
        child: Row(
          children: [
            Avatar(
              name: app.nameOf(from),
              color: Color(app.friendById(from).color),
              size: 30,
              revealName: true,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Icon(
                Icons.arrow_forward,
                size: 14,
                color: c.ink.withValues(alpha: 0.45),
              ),
            ),
            Avatar(
              name: app.nameOf(to),
              color: Color(app.friendById(to).color),
              size: 30,
              revealName: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                formatCents(cents, currency),
                style: mono(15, 700, color: c.ink),
              ),
            ),
            const SizedBox(width: 8),
            Capped(
              child: TintPill(
                label: 'Mark paid',
                fontSize: 11.5,
                background: blocked ? c.chip : null,
                foreground: blocked ? c.muted : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                onTap: blocked
                    ? () => app.showToast(
                        'Assign everything on the bill before settling up.',
                      )
                    : () => app.recordSettlement(groupId, from, to, cents),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One recorded settle-up payment, with its undo.
class _RecordedRow extends StatelessWidget {
  final String groupId;
  final Settlement settlement;
  final String currency;

  const _RecordedRow({
    required this.groupId,
    required this.settlement,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);

    final back = settlement.refund;

    return Semantics(
      label: back
          ? '${app.nameOf(settlement.from)} handed '
                '${formatCents(settlement.cents, currency)} back to '
                '${app.nameOf(settlement.to)}'
          : '${app.nameOf(settlement.from)} paid '
                '${app.nameOf(settlement.to)} '
                '${formatCents(settlement.cents, currency)}',
      child: CompactRow(
        child: Row(
          children: [
            Avatar(
              name: app.nameOf(settlement.from),
              color: Color(app.friendById(settlement.from).color),
              size: 26,
              revealName: true,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Icon(
                // Money going back is not a debt being cleared. After a
                // couple of deletions a column of identical ticks pointing
                // both ways tells the reader nothing at all.
                back ? Icons.undo_rounded : Icons.check,
                size: 13,
                color: back
                    ? Brand.amberIcon
                    : c.okFg.withValues(alpha: 0.7),
              ),
            ),
            Avatar(
              name: app.nameOf(settlement.to),
              color: Color(app.friendById(settlement.to).color),
              size: 26,
              revealName: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatCents(settlement.cents, currency),
                    style: mono(14, 700, color: c.muted),
                  ),
                  if (back)
                    Text(
                      'handed back',
                      style: ui(10.5, 800, color: Brand.amberIcon),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Capped(
              child: TintPill(
                label: 'Undo',
                fontSize: 11.5,
                background: c.chip,
                foreground: c.errorFg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                onTap: () => app.undoSettlementRecord(groupId, settlement),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Somebody is holding money that no longer answers to a debt, because a bill
/// they had settled has since been deleted or edited down.
///
/// The payment itself is not touched - it happened, and unhappening it in the
/// data would make every other figure untrustworthy. What is offered instead
/// is the thing that would happen in real life: give it back, which is
/// recorded as another payment, the other way round.
class _OverpaidRow extends StatelessWidget {
  final String groupId;
  final String person;
  final int cents;
  final String currency;

  const _OverpaidRow({
    required this.groupId,
    required this.person,
    required this.cents,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.amberBg,
        borderRadius: BorderRadius.circular(R.small),
        border: Border.all(color: c.amberLine, width: 1.5),
      ),
      child: CompactRow(
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${formatCents(cents, currency)} of what '
                '${app.nameOf(person)} paid is for a bill that is no longer '
                'here.',
                style: ui(12, 700, color: c.ink, height: 1.4),
              ),
            ),
            const SizedBox(width: 8),
            Capped(
              child: TintPill(
                label: 'Hand it back',
                fontSize: 11.5,
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                onTap: () => app.refundOverpayment(groupId, person),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
