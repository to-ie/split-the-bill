import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

// ---------------------------------------------------------------- containers

/// The standard card: 1.5px solid border, 16px radius.
class BillCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? background;
  final Color? border;
  final VoidCallback? onTap;
  final double radius;
  final double opacity;

  const BillCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 14),
    this.background,
    this.border,
    this.onTap,
    this.radius = R.card,
    this.opacity = 1,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? c.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? c.line, width: 1.5),
      ),
      child: child,
    );
    if (opacity < 1) body = Opacity(opacity: opacity, child: body);
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: body,
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const dash = 3.0, gap = 3.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + dash, size.width), 0),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// The torn-paper rule inside a receipt card.
class DashedRule extends StatelessWidget {
  final EdgeInsets margin;
  final Color? color;
  const DashedRule({
    super.key,
    this.margin = const EdgeInsets.symmetric(vertical: 8),
    this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: CustomPaint(
      painter: _DashPainter(color ?? colors(context).line2),
      size: const Size(double.infinity, 1.5),
    ),
  );
}

class _DashedBoxPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedBoxPainter(this.color, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );

    const dash = 5.0, gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBoxPainter old) => old.color != color;
}

/// Dashed-outline box. Empty states and "add" affordances.
class DashedBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final VoidCallback? onTap;

  const DashedBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = R.card,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = CustomPaint(
      painter: _DashedBoxPainter(colors(context).line2, radius),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: body,
      ),
    );
  }
}

// ------------------------------------------------------------------ buttons

/// The green call to action: 17px/900, 16px radius, 17px padding, and the
/// 2px hard shadow underneath.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? background;
  final double fontSize;
  final EdgeInsets padding;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.background,
    this.fontSize = 17,
    this.padding = const EdgeInsets.all(17),
  });

  @override
  Widget build(BuildContext context) {
    final bg = background ?? Brand.green;
    final shadow = background == null
        ? Brand.greenShadow
        : Color.lerp(bg, Colors.black, 0.18)!;

    return Semantics(
      button: true,
      label: label,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.card),
            boxShadow: [BoxShadow(color: shadow, offset: const Offset(0, 2))],
          ),
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(R.card),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(R.card),
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                padding: padding,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: ui(fontSize, 900, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The quiet full-width button: chip background, ink text, 14px radius.
class ChipButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final double fontSize;

  const ChipButton({
    super.key,
    required this.label,
    this.onPressed,
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Material(
      color: c.chip,
      borderRadius: BorderRadius.circular(R.small),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(R.small),
        child: Container(
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(14),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ui(fontSize, 800, color: c.ink),
          ),
        ),
      ),
    );
  }
}

/// The small solid button beside an input: Done, Add, Create, Copy.
class SolidButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final double fontSize;
  final EdgeInsets padding;
  final double radius;

  const SolidButton({
    super.key,
    required this.label,
    this.onPressed,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
    this.radius = 11,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Material(
      color: c.segBg,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(radius),
        child: Padding(
          padding: padding,
          child: Text(label, style: ui(fontSize, 800, color: c.segFg)),
        ),
      ),
    );
  }
}

/// Dashed full-width affordance: "+ Start a new group", "+ Add another
/// receipt", "+ Add someone new".
class DashedButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final EdgeInsets padding;
  final double radius;
  final bool filled;

  const DashedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.padding = const EdgeInsets.all(12),
    this.radius = R.small,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return DashedBox(
      radius: radius,
      padding: EdgeInsets.zero,
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: padding,
        decoration: filled
            ? BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(radius),
              )
            : null,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: ui(14, 800, color: c.muted),
        ),
      ),
    );
  }
}

/// Green-tinted pill: "Split equally", "Mark paid", "Restore", "Default".
class TintPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? background;
  final Color? foreground;
  final double fontSize;
  final EdgeInsets padding;

  const TintPill({
    super.key,
    required this.label,
    this.onTap,
    this.background,
    this.foreground,
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? c.okBg,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Text(
        label,
        style: ui(fontSize, 800, color: foreground ?? c.okFg),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.pill),
        child: body,
      ),
    );
  }
}

/// Round 40px header/icon button.
class RoundIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;
  final String semanticLabel;
  final double size;
  final Color? background;

  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
    this.size = 40,
    this.background,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    child: Material(
      color: background ?? Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: icon),
        ),
      ),
    ),
  );
}

/// Two-tap destructive button. Outlined when resting, solid red when armed,
/// disarms itself after 2.5 seconds.
class TwoTapButton extends StatefulWidget {
  final String label;
  final String confirmLabel;
  final VoidCallback onConfirmed;

  const TwoTapButton({
    super.key,
    required this.label,
    required this.confirmLabel,
    required this.onConfirmed,
  });

  @override
  State<TwoTapButton> createState() => _TwoTapButtonState();
}

class _TwoTapButtonState extends State<TwoTapButton> {
  bool _armed = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tap() {
    if (_armed) {
      _timer?.cancel();
      setState(() => _armed = false);
      widget.onConfirmed();
      return;
    }
    setState(() => _armed = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _armed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Material(
      color: _armed ? Brand.error : c.card,
      borderRadius: BorderRadius.circular(R.small),
      child: InkWell(
        onTap: _tap,
        borderRadius: BorderRadius.circular(R.small),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.small),
            border: Border.all(
              color: _armed ? Brand.error : c.line2,
              width: 1.5,
            ),
          ),
          child: Text(
            _armed ? widget.confirmLabel : widget.label,
            style: ui(14, 800, color: _armed ? Colors.white : c.errorFg),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ pieces

/// Circular monogram.
class Avatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;

  /// Ring colour. Transparent when not selected.
  final Color? ring;
  final bool dimmed;
  final VoidCallback? onTap;

  /// Tapping shows the name. For rows too narrow to spell it out.
  final bool revealName;

  const Avatar({
    super.key,
    required this.name,
    required this.color,
    this.size = 34,
    this.ring,
    this.dimmed = false,
    this.onTap,
    this.revealName = false,
  });

  String get _initial {
    final t = name.trim();
    return t.isEmpty ? '?' : t.characters.first.toUpperCase();
  }

  /// A friend colour close in luminance to what it sits on disappears. Nudge
  /// it away rather than shipping an avatar nobody can see.
  static Color legibleOn(Color colour, Color surface) {
    final gap = (colour.computeLuminance() - surface.computeLuminance()).abs();
    if (gap >= 0.10) return colour;
    final towards = surface.computeLuminance() < 0.5
        ? Colors.white
        : Colors.black;
    return Color.lerp(colour, towards, 0.42)!;
  }

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    final fill = legibleOn(color, c.card);

    final circle = AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: dimmed ? 0.34 : 1,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.all(color: ring ?? Colors.transparent, width: 2),
        ),
        child: Text(_initial, style: ui(size * 0.40, 900, color: Colors.white)),
      ),
    );

    if (onTap == null && revealName) {
      return Tooltip(
        message: name,
        triggerMode: TooltipTriggerMode.tap,
        preferBelow: false,
        showDuration: const Duration(seconds: 2),
        decoration: BoxDecoration(
          color: Brand.navy,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        textStyle: ui(12, 800, color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Semantics(label: name, child: circle),
      );
    }

    if (onTap == null) return circle;
    return Semantics(
      button: true,
      selected: ring != null,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: circle,
      ),
    );
  }
}

/// Squared monogram tile used on the home and destination rows.
class MonogramTile extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;
  final double size;

  const MonogramTile({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text, style: ui(15, 900, color: foreground)),
  );
}

/// Uppercase muted section label.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: sectionHeader(colors(context).muted));
}

/// A short muted note under a section.
class Note extends StatelessWidget {
  final String text;
  final double fontSize;
  const Note(this.text, {super.key, this.fontSize = 12});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: ui(fontSize, 600, color: colors(context).muted, height: 1.4),
  );
}

/// The chevron used for "opens something".
class Chevron extends StatelessWidget {
  final double size;
  final Color? color;
  const Chevron({super.key, this.size = 16, this.color});

  @override
  Widget build(BuildContext context) => Icon(
    Icons.chevron_right_rounded,
    size: size + 6,
    color: (color ?? colors(context).ink).withValues(alpha: 0.4),
  );
}

// ------------------------------------------------------------------- input

/// Text input styled to the tokens.
class BillField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final bool monoFont;
  final double fontSize;
  final int weight;
  final EdgeInsets padding;
  final double radius;
  final Color? fill;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final int? maxLength;

  /// Restricts what may be typed or pasted. The keyboard type is only a hint
  /// to the keyboard; a paste or a third-party keyboard ignores it.
  final List<TextInputFormatter>? inputFormatters;
  final bool obscure;

  const BillField({
    super.key,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.textAlign = TextAlign.start,
    this.monoFont = false,
    this.fontSize = 15,
    this.weight = 800,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    this.radius = R.input,
    this.fill,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.maxLength,
    this.inputFormatters,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    final style = monoFont
        ? mono(fontSize, weight, color: c.ink)
        : ui(fontSize, weight, color: c.ink);

    OutlineInputBorder border(Color colour) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: colour, width: 1.5),
    );

    return TextField(
      controller: controller,
      autofocus: autofocus,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textAlign: textAlign,
      maxLength: maxLength,
      style: style,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: Brand.green,
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: style.copyWith(color: c.muted),
        isDense: true,
        filled: true,
        fillColor: fill ?? c.card,
        contentPadding: padding,
        border: border(c.line2),
        enabledBorder: border(c.line2),
        focusedBorder: border(Brand.green),
      ),
    );
  }
}

/// 250ms fade-up, the transition the handoff specifies between screens.
Route<T> fadeUpRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 250),
  reverseTransitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, animation, _, child) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.028),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  },
);

/// A confirmation before something irreversible.
///
/// Deliberately not used for deleting a line on the correction screen: that
/// is a small, frequent, easily retyped action and a modal every time made
/// correcting a receipt tedious. It is used for things that cannot be got
/// back, like a whole receipt.
/// What the user chose in [confirmDelete].
enum DeleteChoice {
  /// Backed out. Nothing happens.
  cancel,

  /// Delete, and leave any payments already recorded standing.
  delete,

  /// Delete, and hand back whatever that leaves somebody holding.
  deleteAndRefund,
}

Future<DeleteChoice> confirmDelete(
  BuildContext context, {
  required String title,
  required String detail,
  String confirmLabel = 'Delete it',

  /// Shown when the deletion would leave somebody holding money for a debt
  /// that is about to disappear. Asking here, rather than letting them
  /// discover a balance that has moved for no visible reason, is the whole
  /// point: this is the one moment the user has the context to answer.
  String? creditWarning,
  String? refundLabel,
}) async {
  final c = colors(context);

  final result = await showDialog<DeleteChoice>(
    context: context,
    barrierColor: const Color(0x800A0E18),
    builder: (context) => Dialog(
      backgroundColor: c.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.card),
        side: BorderSide(color: c.line, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The explanation scrolls; the buttons never do. A balance
            // preview for five people at the largest system text is taller
            // than a small phone, and it used to push Keep it and Delete it
            // off the bottom of the screen with no way to reach them.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: ui(17, 900, color: c.ink)),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: c.bg,
                        borderRadius: BorderRadius.circular(R.tight),
                      ),
                      child: Text(
                        detail,
                        style: mono(13, 500, color: c.ink, height: 1.5),
                      ),
                    ),
                    if (creditWarning != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: c.amberBg,
                          borderRadius: BorderRadius.circular(R.small),
                          border: Border.all(color: c.amberLine, width: 1.5),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 17,
                              height: 17,
                              margin: const EdgeInsets.only(top: 1),
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Brand.amberIcon,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '!',
                                style: ui(10.5, 900, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                creditWarning,
                                style: ui(
                                  12.5,
                                  700,
                                  color: c.ink,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (refundLabel != null) ...[
              const SizedBox(height: 12),
              Material(
                color: Brand.green,
                borderRadius: BorderRadius.circular(R.input),
                child: InkWell(
                  onTap: () =>
                      Navigator.of(context).pop(DeleteChoice.deleteAndRefund),
                  borderRadius: BorderRadius.circular(R.input),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(13),
                    child: Text(
                      refundLabel,
                      textAlign: TextAlign.center,
                      style: ui(14, 800, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: c.chip,
                    borderRadius: BorderRadius.circular(R.input),
                    child: InkWell(
                      onTap: () =>
                          Navigator.of(context).pop(DeleteChoice.cancel),
                      borderRadius: BorderRadius.circular(R.input),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(13),
                        child: Text(
                          'Keep it',
                          style: ui(14, 800, color: c.ink),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Material(
                    color: Brand.error,
                    borderRadius: BorderRadius.circular(R.input),
                    child: InkWell(
                      onTap: () =>
                          Navigator.of(context).pop(DeleteChoice.delete),
                      borderRadius: BorderRadius.circular(R.input),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.all(13),
                        child: Text(
                          confirmLabel,
                          style: ui(14, 800, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  return result ?? DeleteChoice.cancel;
}

/// A row too dense to grow without limit: a label, an amount, and a control
/// on one phone-width line.
///
/// Text in the app scales with the system setting, as it should. Past about
/// 1.3x these particular rows have nowhere left to give - the label is already
/// down to nothing and the amount and the button still have to fit - so they
/// overflowed the screen at the largest Android text size on the narrowest
/// phone. Inside one of these the scaling stops at 1.3x; everywhere else in
/// the app it carries on to the full 2x.
///
/// The alternative was making the amount flexible, which forces the label to
/// exactly half the free space at every size and truncates it on an ordinary
/// phone that had room to spare.
class CompactRow extends StatelessWidget {
  final Widget child;
  const CompactRow({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: child);
}

/// Caps how wide a trailing control in a dense row may get.
///
/// A pill or an amount sizes itself to its text, so at the largest system
/// text on the narrowest phone it can be wider than the row it sits in. It
/// cannot be made flexible instead: a flexible child is capped at its share
/// of the free space, which squeezes the label beside it on every ordinary
/// phone that had room to spare. A maximum width does nothing until the
/// control actually gets that wide, and then it ellipsises.
class Capped extends StatelessWidget {
  final Widget child;

  /// Of the screen width.
  final double fraction;

  const Capped({super.key, required this.child, this.fraction = 0.45});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * fraction,
    ),
    child: child,
  );
}
