import 'package:flutter/material.dart';

import '../../app.dart';
import '../../logic/shares.dart';
import '../../model/models.dart';
import '../../model/money.dart';
import '../../parsing/receipt.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/screen_scaffold.dart';
import 'assign_screen.dart';

/// Step 4 of 6. The brief calls this the main screen, not a fallback:
/// parsing will be wrong often enough that editing has to be frictionless.
class CheckScreen extends StatefulWidget {
  const CheckScreen({super.key});

  @override
  State<CheckScreen> createState() => _CheckScreenState();
}

class _CheckScreenState extends State<CheckScreen> with WidgetsBindingObserver {
  String? _editingId;
  bool _editingName = false;
  bool _editingDate = false;

  final _nameCtl = TextEditingController();
  final _dateCtl = TextEditingController();

  /// Points at whichever row editor is currently open.
  final _editorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameCtl.dispose();
    _dateCtl.dispose();
    super.dispose();
  }

  /// The keyboard opening changes the viewport, so the editor has to be
  /// brought back into view after it does. Without this the row you tapped
  /// ends up underneath the keypad on any receipt longer than a few lines.
  @override
  void didChangeMetrics() => _revealEditor();

  void _openEditor(String lineId) {
    setState(() => _editingId = lineId);
    _revealEditor();
  }

  void _revealEditor() {
    if (_editingId == null) return;
    // After the frame, so the editor exists and the viewport has settled.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _editorKey.currentContext;
      if (context == null || !mounted) return;
      final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;
      Scrollable.ensureVisible(
        context,
        // Hard against the top once the keypad is up, so the whole editor
        // fits in what is left. A little breathing room otherwise.
        alignment: keyboardUp ? 0.0 : 0.06,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);
    final draft = app.draft;
    if (draft == null) return const SizedBox.shrink();

    final receipt = draft.receipt;
    final balance = checkBalance(receipt);
    final currency = app.currencyFor(draft.groupId);

    // While a row is open and the keypad is up, screen space is the scarce
    // thing. The screen's own call to action is not what you want mid-edit
    // anyway: the Done inside the editor is.
    final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;
    final editing = _editingId != null;

    return ScreenScaffold(
      title: 'Check the items',
      subtitle: 'Step 4 of 6 · tap or swipe a line',
      discardable: true,
      bodyPadding: const EdgeInsets.fromLTRB(R.pad, 10, R.pad, 0),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hidden entirely when nothing was read to check against, rather
          // than shouting a false negative.
          if (balance.hasTarget) ...[
            _BalanceBanner(
              balanced: balance.balanced,
              itemSum: formatMoney(balance.itemSum, currency),
              target: formatMoney(balance.target, currency),
            ),
            const SizedBox(height: 12),
          ],
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
                _CentredEditable(
                  text: receipt.name.isEmpty
                      ? 'UNTITLED BILL'
                      : receipt.name.toUpperCase(),
                  editing: _editingName,
                  controller: _nameCtl,
                  style: mono(13, 700, color: c.ink, letterSpacing: 1),
                  iconSize: 13,
                  onStart: () {
                    _nameCtl.text = receipt.name;
                    setState(() => _editingName = true);
                  },
                  onDone: () {
                    app.setBillName(_nameCtl.text.trim());
                    setState(() => _editingName = false);
                  },
                ),
                const SizedBox(height: 3),
                _CentredEditable(
                  text: receipt.sub.toUpperCase(),
                  editing: _editingDate,
                  controller: _dateCtl,
                  style: mono(10.5, 400, color: c.muted),
                  iconSize: 11,
                  onStart: () {
                    _dateCtl.text = receipt.date;
                    setState(() => _editingDate = true);
                  },
                  onDone: () {
                    app.setBillDate(_dateCtl.text.trim());
                    setState(() => _editingDate = false);
                  },
                ),
                const DashedRule(margin: EdgeInsets.fromLTRB(0, 12, 0, 4)),
                for (final line in receipt.lines)
                  if (_editingId == line.id)
                    _LineEditor(
                      key: _editorKey,
                      line: line,
                      onDone: () => setState(() => _editingId = null),
                      onDelete: () {
                        app.deleteLine(line.id);
                        setState(() => _editingId = null);
                      },
                    )
                  else
                    Dismissible(
                      key: ValueKey(line.id),
                      direction: DismissDirection.endToStart,
                      background: const _SwipeToDelete(),
                      onDismissed: (_) => app.deleteLine(line.id),
                      child: _LineRow(
                        line: line,
                        currency: currency,
                        onTap: () => _openEditor(line.id),
                      ),
                    ),
                if (receipt.lines.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nothing was read from this photo.\nAdd the lines by hand.',
                      textAlign: TextAlign.center,
                      style: ui(12.5, 700, color: c.muted, height: 1.5),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 2),
                  child: DashedButton(
                    label: '+ Add an item',
                    radius: 10,
                    padding: const EdgeInsets.all(8),
                    onPressed: () {
                      final line = app.addLine();
                      _openEditor(line.id);
                    },
                  ),
                ),
                const DashedRule(margin: EdgeInsets.fromLTRB(0, 6, 0, 8)),
                _RunningTotal(receipt: receipt, currency: currency),
              ],
            ),
          ),
        ],
      ),
      footer: editing && keyboardUp
          ? null
          : PrimaryButton(
              label: 'Next · who had what?',
              onPressed: receipt.splitRows.isEmpty
                  ? null
                  : () =>
                        Navigator.of(context)
                            .push(fadeUpRoute(const AssignScreen())),
            ),
    );
  }
}

class _BalanceBanner extends StatelessWidget {
  final bool balanced;
  final String itemSum;
  final String target;

  const _BalanceBanner({
    required this.balanced,
    required this.itemSum,
    required this.target,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    final bg = balanced ? c.okBg : c.errorTint;
    final fg = balanced ? c.okFg : c.errorFg;
    final message = balanced
        ? 'Adds up. Items match the printed subtotal $target.'
        : "Doesn't add up. Items total $itemSum but the receipt says $target. "
              'Double check the lines.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.small),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            child: Text(balanced ? '✓' : '!', style: ui(12, 900, color: bg)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: ui(13, 800, color: fg, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

/// Centred, tappable text with a faint pencil beside it.
class _CentredEditable extends StatelessWidget {
  final String text;
  final bool editing;
  final TextStyle style;
  final double iconSize;
  final TextEditingController controller;
  final VoidCallback onStart;
  final VoidCallback onDone;

  const _CentredEditable({
    required this.text,
    required this.editing,
    required this.style,
    required this.iconSize,
    required this.controller,
    required this.onStart,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    if (editing) {
      return Row(
        children: [
          Expanded(
            child: BillField(
              controller: controller,
              autofocus: true,
              textAlign: TextAlign.center,
              fontSize: 14,
              weight: 800,
              radius: R.tight,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              onSubmitted: (_) => onDone(),
            ),
          ),
          const SizedBox(width: 8),
          SolidButton(
            label: 'Done',
            fontSize: 12.5,
            radius: R.tight,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            onPressed: onDone,
          ),
        ],
      );
    }
    return Semantics(
      button: true,
      label: 'Edit $text',
      child: InkWell(
        onTap: onStart,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  text,
                  style: style,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.edit_outlined,
                size: iconSize,
                color: c.ink.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The red panel revealed by swiping a line to the left.
class _SwipeToDelete extends StatelessWidget {
  const _SwipeToDelete();

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    margin: const EdgeInsets.symmetric(vertical: 1),
    decoration: BoxDecoration(
      color: Brand.error,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Delete', style: ui(12.5, 800, color: Colors.white)),
        const SizedBox(width: 8),
        const Icon(Icons.delete_outline, size: 18, color: Colors.white),
      ],
    ),
  );
}

class _LineRow extends StatelessWidget {
  final ReceiptLine line;
  final String currency;
  final VoidCallback onTap;

  const _LineRow({
    required this.line,
    required this.currency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    final ignored = !line.kind.isSplittable;
    final label = line.description.isEmpty
        ? '(no description)'
        : line.description;
    final qty = line.quantity > 1 ? ' ×${line.quantity}' : '';
    final deco = ignored ? TextDecoration.lineThrough : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: ignored ? 0.55 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: line.suspicious ? c.amberBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  '$label$qty',
                  style: mono(13, 500, color: c.ink, decoration: deco),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                line.amount == null
                    ? '—'
                    : formatMoney(line.effective, currency),
                style: mono(13, 700, color: c.ink, decoration: deco),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineEditor extends StatefulWidget {
  final ReceiptLine line;
  final VoidCallback onDone;
  final VoidCallback onDelete;

  const _LineEditor({
    super.key,
    required this.line,
    required this.onDone,
    required this.onDelete,
  });

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final TextEditingController _desc = TextEditingController(
    text: widget.line.description,
  );
  late final TextEditingController _amount = TextEditingController(
    text: widget.line.amount == null
        ? ''
        : widget.line.amount!.abs().toStringAsFixed(2),
  );
  late LineKind _kind = widget.line.kind.uiChoice;

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// Writes the editor's current values back to the line.
  ///
  /// Called on every keystroke, not just on Done, so the running total at the
  /// foot of the receipt tracks what is being typed. That is the whole point
  /// of having a total there: you watch it converge on the printed figure.
  void _apply() {
    final app = AppScope.read(context);
    final typed = _amount.text.trim();
    app.updateLine(widget.line.id, (l) {
      return ReceiptLine(
        id: l.id,
        description: _desc.text.trim(),
        amount: typed.isEmpty ? null : parseTyped(typed),
        quantity: l.quantity,
        kind: _kind,
        rawText: l.rawText,
        suspicious: false, // any edit clears the flag
        custom: l.custom,
      );
    });
  }

  void _commit() {
    _apply();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 4, 0, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(R.input),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: BillField(
                  controller: _desc,
                  hint: 'Description',
                  autofocus: true,
                  fontSize: 14,
                  weight: 700,
                  radius: R.tight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  onChanged: (_) => _apply(),
                  onSubmitted: (_) => _commit(),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 76,
                child: BillField(
                  controller: _amount,
                  hint: '0.00',
                  monoFont: true,
                  fontSize: 14,
                  weight: 700,
                  textAlign: TextAlign.end,
                  radius: R.tight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _apply(),
                  onSubmitted: (_) => _commit(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 5,
            children: [
              for (final k in LineKind.uiChoices)
                GestureDetector(
                  onTap: () {
                    setState(() => _kind = k);
                    _apply();
                  },
                  child: TintPill(
                    label: k.chipLabel,
                    background: _kind == k ? Brand.green : c.chip,
                    foreground: _kind == k ? Colors.white : c.muted,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // One line: this is a reference, and the space it would take on a
          // second line is space the keypad wants.
          Text(
            'OCR read: “${widget.line.rawText.replaceAll('\n', ' ')}”',
            style: ui(11, 600, color: c.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Semantics(
                button: true,
                label: 'Delete this line',
                child: InkWell(
                  onTap: widget.onDelete,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFE3B7AE),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: Brand.error,
                    ),
                  ),
                ),
              ),
              SolidButton(
                label: 'Done',
                fontSize: 12.5,
                radius: R.pill,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                onPressed: _commit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the lines on screen currently add up to, against what the receipt
/// says. The printed figures alone are not enough to check your work by: they
/// tell you what the paper claims, not whether the numbers you have typed
/// match it.
class _RunningTotal extends StatelessWidget {
  final Receipt receipt;
  final String currency;

  const _RunningTotal({required this.receipt, required this.currency});

  @override
  Widget build(BuildContext context) {
    final c = colors(context);

    final items = receipt.itemsCents;
    final extras = receipt.extrasCents;
    final discounts = receipt.discountsCents;
    final total = receipt.grandCents;

    final printed = receipt.printedTotal;
    final printedCents = printed == null ? null : toCents(printed);
    final difference = printedCents == null ? null : total - printedCents;
    final matches = difference != null && difference.abs() < 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(label: 'ITEMS', value: formatCents(items, currency)),
        if (extras != 0)
          _Row(label: 'EXTRAS', value: formatCents(extras, currency)),
        if (discounts != 0)
          _Row(
            label: 'DISCOUNTS',
            value: formatCents(discounts, currency),
            colour: c.okFg,
          ),
        const DashedRule(margin: EdgeInsets.fromLTRB(0, 8, 0, 6)),
        _Row(
          label: 'YOUR TOTAL',
          value: formatCents(total, currency),
          strong: true,
        ),
        if (difference != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Row(
              children: [
                Icon(
                  matches ? Icons.check_circle : Icons.error_outline,
                  size: 14,
                  color: matches ? c.okFg : c.errorFg,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    matches
                        ? 'Matches the printed total.'
                        : difference > 0
                        ? '${formatCents(difference, currency)} more '
                              'than the printed total.'
                        : '${formatCents(-difference, currency)} less '
                              'than the printed total.',
                    style: ui(11.5, 700, color: matches ? c.okFg : c.errorFg),
                  ),
                ),
              ],
            ),
          ),
        if (receipt.printedSubtotal != null ||
            receipt.printedTotal != null) ...[
          const DashedRule(margin: EdgeInsets.fromLTRB(0, 10, 0, 8)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('AS PRINTED', style: mono(10, 400, color: c.muted)),
          ),
          const SizedBox(height: 2),
          if (receipt.printedSubtotal != null)
            _Row(
              label: 'SUBTOTAL',
              value: formatMoney(receipt.printedSubtotal!, currency),
              muted: true,
            ),
          if (receipt.printedTotal != null)
            _Row(
              label: 'TOTAL',
              value: formatMoney(receipt.printedTotal!, currency),
              muted: true,
            ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final bool muted;
  final Color? colour;

  const _Row({
    required this.label,
    required this.value,
    this.strong = false,
    this.muted = false,
    this.colour,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    final style = strong
        ? mono(13.5, 700, color: colour ?? c.ink)
        : mono(
            12,
            muted ? 400 : 500,
            color: colour ?? (muted ? c.muted : c.ink),
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        children: [
          // The label gives way first: the amount is the part worth reading.
          Expanded(
            child: Text(
              label,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(value, style: style),
        ],
      ),
    );
  }
}
