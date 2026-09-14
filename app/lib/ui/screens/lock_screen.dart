import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// The PIN gate. Shown before anything else when a PIN is set.
///
/// The PIN protects the receipts on this device from someone holding the
/// phone. It is not encryption: the data on disk is still plain JSON, and
/// anyone with access to the filesystem can read it. Saying so plainly is
/// better than implying a guarantee the app does not provide.
class LockScreen extends StatefulWidget {
  /// Returns true if the four digits are right. The screen never sees the
  /// stored PIN, because there is no stored PIN to see.
  final bool Function(String) verify;
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.verify, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  String _entered = '';
  bool _wrong = false;

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _press(String digit) {
    if (_entered.length >= 4) return;
    setState(() {
      _entered += digit;
      _wrong = false;
    });
    if (_entered.length == 4) _check();
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _wrong = false;
    });
  }

  Future<void> _check() async {
    if (widget.verify(_entered)) {
      widget.onUnlocked();
      return;
    }
    setState(() => _wrong = true);
    await _shake.forward(from: 0);
    if (mounted) setState(() => _entered = '');
  }

  @override
  Widget build(BuildContext context) {
    final c = colors(context);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const _Logo(),
            const SizedBox(height: 18),
            Text(
              _wrong ? 'Wrong PIN' : 'Enter your PIN',
              style: ui(17, 900, color: _wrong ? c.errorFg : c.ink),
            ),
            const SizedBox(height: 18),
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) {
                // Two quick cycles left and right, decaying to nothing.
                final t = _shake.value;
                final dx = t == 0
                    ? 0.0
                    : (1 - t) * 10 * (t * 8 % 2 < 1 ? 1 : -1);
                return Transform.translate(offset: Offset(dx, 0), child: child);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _entered.length
                            ? (_wrong ? c.errorFg : Brand.green)
                            : Colors.transparent,
                        border: Border.all(
                          color: i < _entered.length
                              ? (_wrong ? c.errorFg : Brand.green)
                              : c.line2,
                          width: 2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 0, 36, 10),
              child: Column(
                children: [
                  for (final row in const [
                    ['1', '2', '3'],
                    ['4', '5', '6'],
                    ['7', '8', '9'],
                  ])
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [for (final d in row) _Key(d, () => _press(d))],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      const _KeySpacer(),
                      _Key('0', () => _press('0')),
                      _Key(
                        '',
                        _backspace,
                        icon: Icons.backspace_outlined,
                        semanticLabel: 'Delete',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 18),
              child: Text(
                'The PIN keeps the phone out of other hands. It is not '
                'encryption.',
                textAlign: TextAlign.center,
                style: ui(11.5, 600, color: c.muted, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? semanticLabel;

  const _Key(this.label, this.onTap, {this.icon, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: icon == null ? c.card : Colors.transparent,
          shape: CircleBorder(
            side: icon == null
                ? BorderSide(color: c.line, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 68,
              height: 68,
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 22, color: c.muted)
                    : Text(label, style: ui(24, 700, color: c.ink)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeySpacer extends StatelessWidget {
  const _KeySpacer();

  @override
  Widget build(BuildContext context) =>
      const Padding(padding: EdgeInsets.all(6), child: SizedBox(width: 68));
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    const image = Image(
      image: AssetImage('assets/images/logo.png'),
      width: 96,
      semanticLabel: 'Split the Bill',
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: const Offset(0, 6),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: const ColorFiltered(
              colorFilter: ColorFilter.mode(
                Color(0x291C222C),
                BlendMode.srcATop,
              ),
              child: image,
            ),
          ),
        ),
        image,
      ],
    );
  }
}
