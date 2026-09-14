import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'common.dart';

/// Every screen. Chevron back at 40x40, title at 20/900, an uppercase
/// subtitle line, and optional header actions on the right.
///
/// The body scrolls; [footer] is pinned under it, which is what the
/// prototype's `margin-top:auto` achieves.
class ScreenScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget body;
  final Widget? footer;
  final bool showBack;

  /// Shows the two-tap discard control on the right.
  final bool discardable;
  final List<Widget> actions;

  /// Something drawn over the whole screen, e.g. a popup menu.
  final Widget? overlay;

  final bool scrollable;
  final EdgeInsets bodyPadding;

  const ScreenScaffold({
    super.key,
    required this.title,
    this.subtitle = '',
    required this.body,
    this.footer,
    this.showBack = true,
    this.discardable = false,
    this.actions = const [],
    this.overlay,
    this.scrollable = true,
    this.bodyPadding = const EdgeInsets.fromLTRB(R.pad, 14, R.pad, 0),
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);

    final content = Padding(padding: bodyPadding, child: body);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                  child: Row(
                    children: [
                      if (showBack)
                        RoundIconButton(
                          semanticLabel: 'Back',
                          onTap: () => Navigator.of(context).maybePop(),
                          icon: Icon(
                            Icons.chevron_left_rounded,
                            size: 28,
                            color: c.ink,
                          ),
                        )
                      else
                        const SizedBox(width: 6),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: ui(20, 900, color: c.ink),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  subtitle.toUpperCase(),
                                  style: screenSubtitle(c.muted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      // A header action is capped rather than allowed to
                      // take the whole bar. At large text sizes the "Split
                      // equally" pill grew until it pushed the title off the
                      // screen; it ellipsises now instead.
                      ...actions.map(
                        (a) => ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 148),
                          child: a,
                        ),
                      ),
                      if (discardable) const DiscardButton(),
                    ],
                  ),
                ),
                Expanded(
                  child: scrollable
                      ? SingleChildScrollView(child: content)
                      : content,
                ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(R.pad, 16, R.pad, 22),
                    child: footer!,
                  ),
              ],
            ),
            ?overlay,
          ],
        ),
      ),
    );
  }
}

/// Two-tap discard: a bare ✕ that turns into a red "Discard?" pill, then
/// abandons the flow. Disarms after 2.5 seconds.
class DiscardButton extends StatefulWidget {
  const DiscardButton({super.key});

  @override
  State<DiscardButton> createState() => _DiscardButtonState();
}

class _DiscardButtonState extends State<DiscardButton> {
  bool _armed = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tap() {
    final app = AppScope.read(context);
    if (_armed) {
      _timer?.cancel();
      app.discardDraft();
      Navigator.of(context).popUntil((r) => r.isFirst);
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
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: _armed ? c.errorTint : Colors.transparent,
        borderRadius: BorderRadius.circular(R.pill),
        child: InkWell(
          onTap: _tap,
          borderRadius: BorderRadius.circular(R.pill),
          child: Container(
            height: 32,
            constraints: const BoxConstraints(minWidth: 36),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _armed
                ? Text('Discard?', style: ui(12.5, 800, color: c.errorFg))
                : Icon(Icons.close, size: 17, color: c.muted),
          ),
        ),
      ),
    );
  }
}
