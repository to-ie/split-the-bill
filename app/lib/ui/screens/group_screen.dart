import 'package:flutter/material.dart';

import '../../app.dart';
import '../../logic/receipt_payments.dart';
import '../../model/models.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/screen_scaffold.dart';
import 'group_summary_screen.dart';
import 'people_screen.dart';
import 'check_screen.dart';
import 'receipt_view_screen.dart';

class GroupScreen extends StatefulWidget {
  final String groupId;
  const GroupScreen({super.key, required this.groupId});

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends State<GroupScreen> {
  final _name = TextEditingController();
  bool _menu = false;
  bool _currency = false;
  String? _rowMenu;
  bool _seeded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);
    final g = app.groupById(widget.groupId);
    if (g == null) return const SizedBox.shrink();

    if (!_seeded) {
      _name.text = g.name;
      _seeded = true;
    }

    // How far each bill has been paid back, derived from the settle-up
    // payments recorded on the group summary.
    final payments = receiptPayments(g);

    return ScreenScaffold(
      title: g.name,
      subtitle: 'Group · name, currency, receipts',
      bodyPadding: const EdgeInsets.fromLTRB(R.pad, 14, R.pad, 26),
      actions: [
        RoundIconButton(
          semanticLabel: 'Group options',
          onTap: () => setState(() {
            _menu = !_menu;
            _currency = false;
          }),
          icon: Icon(Icons.more_vert, size: 20, color: c.ink),
        ),
      ],
      overlay: _menu ? _menuPanel(app, g, c) : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Name'),
          const SizedBox(height: 8),
          BillField(
            controller: _name,
            hint: 'Group name',
            onChanged: (v) => app.renameGroup(g.id, v),
          ),
          const SizedBox(height: 18),

          const SectionLabel('Members'),
          const SizedBox(height: 8),
          BillCard(
            radius: R.small,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final id in g.members)
                  Avatar(
                    name: app.nameOf(id),
                    color: Color(app.friendById(id).color),
                    size: 34,
                    revealName: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // There is no separate membership list to edit: a group's members
          // are whoever has been on one of its receipts.
          const Note(
            'Whoever has been on a receipt in this group. '
            'Tap a circle for a name.',
          ),
          const SizedBox(height: 18),

          const SectionLabel('Receipts · meals, tickets, anything'),
          const SizedBox(height: 10),
          for (final r in g.receipts) ...[
            _ReceiptRow(
              groupId: g.id,
              receipt: r,
              payment: payments[r.id],
              menuOpen: _rowMenu == r.id,
              onMenu: () =>
                  setState(() => _rowMenu = _rowMenu == r.id ? null : r.id),
              onClose: () => setState(() => _rowMenu = null),
            ),
            const SizedBox(height: R.gap),
          ],
          // An empty group used to show "No receipts yet" and "Add another
          // receipt" as two dashed boxes stacked against each other, which
          // read as one broken control and offered "another" of nothing.
          DashedButton(
            label: g.receipts.isEmpty
                ? '+ Add the first receipt'
                : '+ Add another receipt',
            onPressed: () {
              app.startFlow();
              app.setDestination(g.id);
              Navigator.of(context).push(fadeUpRoute(const PeopleScreen()));
            },
          ),
          const SizedBox(height: 22),
          PrimaryButton(
            label: 'Group summary · who owes what overall',
            fontSize: 16,
            padding: const EdgeInsets.all(16),
            onPressed: () =>
                Navigator.of(context)
                    .push(fadeUpRoute(GroupSummaryScreen(groupId: g.id))),
          ),
        ],
      ),
    );
  }

  /// A floating popup anchored under the kebab, as in the prototype.
  Widget _menuPanel(AppState app, Group g, BillColors c) {
    Widget item(String label, VoidCallback onTap, {Widget? trailing}) =>
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: ui(14, 800, color: c.ink)),
                ),
                ?trailing,
              ],
            ),
          ),
        );

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _menu = false),
        child: Stack(
          children: [
            // A Stack lays a positioned child out against unbounded
            // constraints unless both horizontal edges are given, and a
            // Column that stretches then asks for infinite width and throws
            // during layout. That is why this menu never appeared: it was
            // built every time and failed before it could paint.
            Positioned(
              top: 52,
              left: 16,
              right: 16,
              child: Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    color: c.card,
                    borderRadius: BorderRadius.circular(R.small),
                    elevation: 10,
                    shadowColor: const Color(0x2E000000),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 240,
                        maxWidth: 300,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(R.small),
                        border: Border.all(color: c.line, width: 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          item('Go to home', () {
                            setState(() => _menu = false);
                            Navigator.of(context).popUntil((r) => r.isFirst);
                          }),
                          item(
                            'Currency',
                            () => setState(() => _currency = !_currency),
                            trailing: Text(
                              g.currency ?? 'Default',
                              style: ui(12.5, 800, color: c.muted),
                            ),
                          ),
                          if (_currency)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(color: c.line),
                                ),
                              ),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _curChip(
                                    'Default',
                                    g.currency == null,
                                    () => app.setGroupCurrency(g.id, null),
                                    c,
                                  ),
                                  for (final sym in app.settings.currencies)
                                    _curChip(
                                      sym,
                                      g.currency == sym,
                                      () => app.setGroupCurrency(g.id, sym),
                                      c,
                                    ),
                                ],
                              ),
                            ),
                          item(
                            g.archived
                                ? 'Restore this group'
                                : 'Archive this group',
                            () {
                              final archiving = !g.archived;
                              setState(() => _menu = false);
                              app.setArchived(g.id, archiving);
                              // Archiving is putting the group away. Staying on
                              // it afterwards looks as though nothing happened.
                              // Restoring leaves you on it, ready to use it.
                              if (archiving) {
                                Navigator.of(context)
                                    .popUntil((r) => r.isFirst);
                              }
                            },
                          ),
                          _DeleteItem(
                            onConfirmed: () {
                              app.deleteGroup(g.id);
                              Navigator.of(context).popUntil((r) => r.isFirst);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _curChip(
    String label,
    bool selected,
    VoidCallback onTap,
    BillColors c,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? Brand.green : c.chip,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: c.line),
      ),
      child: Text(
        label,
        style: ui(12.5, 800, color: selected ? Colors.white : c.ink),
      ),
    ),
  );
}

/// Two-tap delete row at the bottom of the group menu.
class _DeleteItem extends StatefulWidget {
  final VoidCallback onConfirmed;
  const _DeleteItem({required this.onConfirmed});

  @override
  State<_DeleteItem> createState() => _DeleteItemState();
}

class _DeleteItemState extends State<_DeleteItem> {
  bool _armed = false;

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return InkWell(
      onTap: () {
        if (_armed) {
          widget.onConfirmed();
          return;
        }
        setState(() => _armed = true);
        Future.delayed(const Duration(milliseconds: 2500), () {
          if (mounted) setState(() => _armed = false);
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        color: _armed ? Brand.error : c.card,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Text(
          _armed ? 'Tap again to delete for good' : 'Delete this group',
          style: ui(14, 800, color: _armed ? Colors.white : c.errorFg),
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String groupId;
  final Receipt receipt;
  final ReceiptPayment? payment;
  final bool menuOpen;
  final VoidCallback onMenu;
  final VoidCallback onClose;

  const _ReceiptRow({
    required this.groupId,
    required this.receipt,
    required this.payment,
    required this.menuOpen,
    required this.onMenu,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);

    return BillCard(
      radius: R.small,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.of(context).push(
                    fadeUpRoute(
                      ReceiptViewScreen(
                        groupId: groupId,
                        receiptId: receipt.id,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        receipt.name,
                        style: ui(14, 800, color: c.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(receipt.sub, style: ui(12, 600, color: c.muted)),
                      Text(
                        'Paid by ${app.nameOf(receipt.paidBy)}',
                        style: ui(12, 700, color: c.okFg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Its own line: at phone width there is not room beside
                      // the payer's name, and neither is worth clipping.
                      if (payment != null &&
                          payment!.progress != PaymentProgress.none)
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _PaidBadge(payment: payment!),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                app.moneyCents(receipt.grandCents, groupId: groupId),
                style: mono(13.5, 700, color: c.ink),
              ),
              RoundIconButton(
                size: 30,
                semanticLabel: 'Receipt options',
                background: menuOpen ? c.chip : null,
                onTap: onMenu,
                icon: Icon(Icons.more_vert, size: 17, color: c.muted),
              ),
            ],
          ),
          if (menuOpen)
            Padding(
              padding: const EdgeInsets.only(top: 11),
              child: Row(
                children: [
                  Expanded(
                    child: _MenuChip(
                      label: 'Edit',
                      background: c.chip,
                      foreground: c.ink,
                      onTap: () {
                        onClose();
                        app.editReceipt(groupId, receipt.id);
                        Navigator.of(context)
                            .push(fadeUpRoute(const CheckScreen()));
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MenuChip(
                      label: 'Delete',
                      background: c.errorTint,
                      foreground: c.errorFg,
                      onTap: () async {
                        // Payments already made are not unmade by deleting
                        // the bill they were for, so anyone who has settled
                        // against it would be left holding money for a debt
                        // that no longer exists. Say so here, while there is
                        // still something to point at, rather than letting a
                        // balance move later for no visible reason.
                        final credit = app.creditIfReceiptDeleted(
                          groupId,
                          receipt.id,
                        );
                        final owed = credit.entries
                            .map(
                              (e) =>
                                  '${app.nameOf(e.key)} '
                                  '${app.moneyCents(e.value, groupId: groupId)}',
                            )
                            .join(', ');

                        final choice = await confirmDelete(
                          context,
                          title: 'Delete this receipt?',
                          detail:
                              '${receipt.name}\n'
                              '${app.moneyCents(receipt.grandCents, groupId: groupId)}',
                          confirmLabel: 'Delete it',
                          creditWarning: credit.isEmpty
                              ? null
                              : 'Already settled against this bill: $owed. '
                                    'Deleting it leaves that in credit, and '
                                    'owed back.',
                          refundLabel: credit.isEmpty
                              ? null
                              : 'Delete and hand the money back',
                        );
                        if (choice == DeleteChoice.cancel) return;
                        onClose();
                        app.deleteReceipt(
                          groupId,
                          receipt.id,
                          refund: choice == DeleteChoice.deleteAndRefund,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MenuChip extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  const _MenuChip({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.all(9),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: ui(13, 800, color: foreground),
        ),
      ),
    ),
  );
}

/// How much of a bill has been paid back, derived from the settle-up
/// payments recorded on the group summary. It only appears once money has
/// actually changed hands, or once the whole group is square.
class _PaidBadge extends StatelessWidget {
  final ReceiptPayment payment;

  const _PaidBadge({required this.payment});

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    final full = payment.progress == PaymentProgress.full;

    final settled = payment.settledBy.length;
    final total = payment.debtors.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: full ? c.okBg : c.amberBg,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            full ? Icons.check_circle : Icons.timelapse,
            size: 11,
            color: full ? c.okFg : Brand.amberIcon,
          ),
          const SizedBox(width: 4),
          // Flexible so a narrow row can never overflow the badge, whatever
          // the count string comes out as.
          Flexible(
            child: Text(
              full ? 'Paid' : 'Part paid · $settled/$total',
              style: ui(11, 800, color: full ? c.okFg : Brand.amberIcon),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
