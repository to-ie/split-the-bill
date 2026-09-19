import 'package:flutter/material.dart';

import '../../app.dart';
import '../../logic/share_text.dart';
import '../../logic/shares.dart';
import '../../model/money.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/screen_scaffold.dart';
import '../widgets/share_sheet.dart';
import 'group_summary_screen.dart';

/// Step 6 of 6.
class SummaryScreen extends StatelessWidget {
  const SummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);
    final draft = app.draft;
    if (draft == null) return const SizedBox.shrink();

    final receipt = draft.receipt;
    final currency = app.currencyFor(draft.groupId);
    final shares = computeShares(receipt);
    final group = app.groupById(draft.groupId);

    return ScreenScaffold(
      title: 'This receipt',
      subtitle: 'Step 6 of 6',
      discardable: true,
      bodyPadding: const EdgeInsets.fromLTRB(R.pad, 10, R.pad, 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeroPanel(
            title: receipt.name.isEmpty ? 'Untitled bill' : receipt.name,
            subtitle: '${receipt.party.length} people · ${receipt.date}',
            amount: formatCents(receipt.grandCents, currency),
          ),
          const SizedBox(height: R.gap),

          // Paid by: a single row, label left, avatars right.
          BillCard(
            radius: R.small,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Text(
                  'PAID BY',
                  style: ui(11.5, 900, color: c.muted, letterSpacing: 0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final id in receipt.party)
                        Avatar(
                          name: app.nameOf(id),
                          color: Color(app.friendById(id).color),
                          size: 34,
                          ring: receipt.paidBy == id ? Brand.green : null,
                          dimmed: receipt.paidBy != id,
                          revealName: true,
                          onTap: () => app.setPaidBy(id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (group != null && !group.oneOff) ...[
            const SizedBox(height: R.gap),
            // Says where this bill has landed. It used to be a second way to
            // reach the group total; Done goes there now, so a control that
            // did the same thing beside it was just noise.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: c.okBg,
                borderRadius: BorderRadius.circular(R.small),
              ),
              child: Text(
                'Part of ${group.name}. Done shows the group total.',
                style: ui(13, 800, color: c.okFg),
              ),
            ),
          ],

          const SizedBox(height: 12),
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

          if (shares.hasUnassigned)
            AmberBanner(
              text:
                  '${formatCents(shares.unassignedCents, currency)} is not '
                  'assigned to anyone yet.',
              onTap: () => Navigator.of(context).pop(),
            ),
        ],
      ),
      footer: Column(
        children: [
          PrimaryButton(
            label: 'Done',
            onPressed: () {
              // Finishing a bill lands on the group it belongs to, not back
              // at the start. The question anybody has after adding a receipt
              // is what it did to the totals, and that is the next screen.
              //
              // A one-off split has no group worth looking at, so it goes
              // home as before.
              final navigator = Navigator.of(context);
              final id = app.finishFlow();
              final group = app.groupById(id);
              navigator.popUntil((r) => r.isFirst);
              if (group != null && !group.oneOff) {
                navigator.push(fadeUpRoute(GroupSummaryScreen(groupId: id)));
              }
            },
          ),
          const SizedBox(height: R.gap),
          ChipButton(
            label: 'Share the split · send a message',
            onPressed: () => showShareSheet(
              context,
              'Send the split',
              shareReceiptText(app, receipt, currency),
            ),
          ),
        ],
      ),
    );
  }
}

/// The navy summary panel: title and subtitle on the left, total on the right.
class HeroPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String amount;

  /// A word under the figure saying what it is, when that is not obvious.
  final String? label;

  const HeroPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.label,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    decoration: BoxDecoration(
      color: Brand.navy,
      borderRadius: BorderRadius.circular(R.card),
    ),
    child: CompactRow(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ui(15, 800, color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: ui(
                    12.5,
                    600,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(amount, style: mono(20, 700, color: Colors.white)),
              if (label != null)
                Text(
                  label!,
                  style: ui(
                    11,
                    800,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// One row under a person's total.
class CardLine {
  final String label;
  final String amount;
  final Color? color;

  /// What this row is made of. On the group summary a row is a whole bill,
  /// and these are the items that person actually had on it.
  final List<CardLine> detail;

  const CardLine(
    this.label,
    this.amount, {
    this.color,
    this.detail = const [],
  });
}

/// A person's card: avatar, name, total, then an itemised list under a
/// dashed rule. Used on both summary screens.
class PersonCard extends StatelessWidget {
  final String name;
  final Color color;
  final String amount;
  final Color? amountColor;
  final String? status;

  final List<CardLine> lines;

  /// Anything that has to be said about this person specifically. Inside the
  /// card, because a strip floating between two cards belongs to neither.
  final Widget? footer;

  const PersonCard({
    super.key,
    required this.name,
    required this.color,
    required this.amount,
    this.amountColor,
    this.status,
    required this.lines,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return BillCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Avatar(name: name, color: color, size: 34, revealName: true),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: ui(16, 900, color: c.ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: mono(17, 700, color: amountColor ?? c.ink),
                  ),
                  if (status != null)
                    Text(status!, style: ui(11, 800, color: c.muted)),
                ],
              ),
            ],
          ),
          if (lines.isNotEmpty) ...[
            DashedRule(
              margin: const EdgeInsets.fromLTRB(0, 10, 0, 6),
              color: c.line,
            ),
            for (final line in lines) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        line.label,
                        style: ui(13, 600, color: c.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      line.amount,
                      style: mono(13, 400, color: line.color ?? c.muted),
                    ),
                  ],
                ),
              ),
              // The items behind the figure, set in from the left and quieter,
              // so the bill totals still read as the list and these read as
              // the working behind them.
              //
              // A bill with one item for this person would otherwise print
              // the same amount twice, one under the other. The line still
              // earns its place - it is what says "shared four ways" - so it
              // keeps the label and loses the repeated figure.
              if (line.detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final d in line.detail)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1.5),
                          child: Row(
                            children: [
                              Container(
                                width: 3,
                                height: 3,
                                margin: const EdgeInsets.only(right: 7),
                                decoration: BoxDecoration(
                                  color: c.muted.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  d.label,
                                  style: ui(
                                    11.5,
                                    600,
                                    color: c.muted.withValues(alpha: 0.85),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (line.detail.length > 1 ||
                                  d.amount != line.amount) ...[
                                const SizedBox(width: 8),
                                Text(
                                  d.amount,
                                  style: mono(
                                    11.5,
                                    400,
                                    color: c.muted.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ],
          if (footer != null) ...[const SizedBox(height: 10), footer!],
        ],
      ),
    );
  }
}

/// The tappable amber warning.
class AmberBanner extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;

  const AmberBanner({super.key, required this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Material(
      color: c.amberBg,
      borderRadius: BorderRadius.circular(R.small),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.small),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.small),
            border: Border.all(color: c.amberLine, width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(top: 1),
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Brand.amberIcon,
                  shape: BoxShape.circle,
                ),
                child: Text('!', style: ui(11, 900, color: Colors.white)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  onTap == null ? text : '$text Tap to finish assigning.',
                  style: ui(13, 800, color: c.ink, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
