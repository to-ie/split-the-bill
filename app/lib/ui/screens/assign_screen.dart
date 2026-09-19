import 'package:flutter/material.dart';

import '../../app.dart';
import '../../logic/shares.dart';
import '../../model/money.dart';
import '../../parsing/receipt.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/screen_scaffold.dart';
import 'summary_screen.dart';

/// Step 5 of 6. Extras and discounts get assigned here too, not just items:
/// who shares the service charge is a decision, not an apportionment.
class AssignScreen extends StatelessWidget {
  const AssignScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final draft = app.draft;
    if (draft == null) return const SizedBox.shrink();

    final receipt = draft.receipt;
    final currency = app.currencyFor(draft.groupId);
    final unassigned = unassignedRowCount(receipt, receipt.party);
    final clearing = app.everythingAssignedToEveryone;

    return ScreenScaffold(
      title: 'Who had what?',
      subtitle: 'Step 5 of 6',
      discardable: true,
      bodyPadding: const EdgeInsets.fromLTRB(R.pad, 12, R.pad, 0),
      actions: [
        TintPill(
          label: clearing ? 'Clear all' : 'Split equally',
          onTap: app.splitEquallyOrClear,
        ),
        const SizedBox(width: 4),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in receipt.splitRows) ...[
            _AssignRow(
              line: row,
              party: receipt.party,
              assigned: receipt.assign[row.id] ?? const [],
              currency: currency,
            ),
            const SizedBox(height: R.gap),
          ],
        ],
      ),
      footer: PrimaryButton(
        label: unassigned == 0
            ? 'See the summary'
            : 'Summary · $unassigned ${unassigned == 1 ? 'item' : 'items'} unassigned',
        background: unassigned == 0 ? null : const Color(0xFFE2A21B),
        onPressed: () =>
            Navigator.of(context).push(fadeUpRoute(const SummaryScreen())),
      ),
    );
  }
}

class _AssignRow extends StatelessWidget {
  final ReceiptLine line;
  final List<String> party;
  final List<String> assigned;
  final String currency;

  const _AssignRow({
    required this.line,
    required this.party,
    required this.assigned,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);

    final live = assigned.where(party.contains).toList();
    final each = live.isEmpty
        ? null
        : allocate(toCents(line.effective), live.length).first;

    return BillCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  line.description.isEmpty
                      ? '(no description)'
                      : line.description,
                  style: ui(15, 800, color: c.ink),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatMoney(line.effective, currency),
                style: mono(14, 700, color: c.ink),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final id in party)
                      Avatar(
                        name: app.nameOf(id),
                        color: Color(app.friendById(id).color),
                        size: 36,
                        ring: live.contains(id) ? Brand.green : null,
                        dimmed: !live.contains(id),
                        revealName: true,
                        onTap: () => app.toggleAssign(line.id, id),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                each == null
                    ? 'Unassigned'
                    : '${formatCents(each, currency)} each',
                style: ui(12, 800, color: each == null ? Brand.error : c.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
