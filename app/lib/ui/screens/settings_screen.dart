import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app.dart';
import '../../model/models.dart';
import '../../state/app_state.dart';
import '../../state/store.dart';
import '../../version.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/screen_scaffold.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _myName = TextEditingController();
  final _newFriend = TextEditingController();
  final _pin = TextEditingController();
  bool _addCurrency = false;
  bool _changingPin = false;
  bool _seeded = false;

  @override
  void dispose() {
    _myName.dispose();
    _newFriend.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _addFriend(AppState app) {
    if (_newFriend.text.trim().isEmpty) return;
    app.addFriend(_newFriend.text);
    _newFriend.clear();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);

    if (!_seeded) {
      _myName.text = app.settings.myName;
      _seeded = true;
    }

    return ScreenScaffold(
      title: 'Settings',
      subtitle: 'Everything stays on this phone',
      bodyPadding: const EdgeInsets.fromLTRB(R.pad, 14, R.pad, 26),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Your name'),
          const SizedBox(height: 8),
          BillField(
            controller: _myName,
            hint: 'e.g. Sam',
            onChanged: app.setMyName,
          ),
          const SizedBox(height: 8),
          const Note('Shown instead of “You” in summaries and shared texts.'),
          const SizedBox(height: 18),

          const SectionLabel('Appearance'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: c.chip,
              borderRadius: BorderRadius.circular(R.input),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _Segment(
                    label: 'Light',
                    selected: !app.settings.dark,
                    onTap: () => app.setDark(false),
                  ),
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: _Segment(
                    label: 'Dark',
                    selected: app.settings.dark,
                    onTap: () => app.setDark(true),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          const SectionLabel('Currencies'),
          const SizedBox(height: 8),
          _ListCard(
            children: [
              for (final sym in app.settings.currencies)
                _RowPad(
                  child: CompactRow(
                    child: Row(
                      children: [
                        Container(
                          constraints: const BoxConstraints(minWidth: 38),
                          height: 30,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: c.chip,
                            borderRadius: BorderRadius.circular(R.tight),
                          ),
                          child: Text(sym, style: mono(13, 900, color: c.ink)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _currencyName(sym),
                            style: ui(14, 800, color: c.ink),
                          ),
                        ),
                        if (sym == app.settings.appCurrency)
                          const Capped(
                            child: TintPill(
                              label: 'Default',
                              fontSize: 11.5,
                              padding: EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 6,
                              ),
                            ),
                          )
                        else
                          Capped(
                            child: TintPill(
                              label: 'Set default',
                              fontSize: 11.5,
                              background: c.chip,
                              foreground: c.muted,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 6,
                              ),
                              onTap: () => app.setAppCurrency(sym),
                            ),
                          ),
                        const SizedBox(width: 8),
                        _RemoveButton(
                          semanticLabel: 'Remove $sym',
                          onTap: () => app.removeCurrency(sym),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_addCurrency)
                _RowPad(
                  divider: false,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (sym, name) in currencyCatalogue)
                        if (!app.settings.currencies.contains(sym))
                          GestureDetector(
                            onTap: () {
                              app.addCurrency(sym);
                              setState(() => _addCurrency = false);
                            },
                            child: TintPill(
                              label: '+ $sym  $name',
                              fontSize: 12.5,
                              background: c.chip,
                              foreground: c.ink,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 7,
                              ),
                            ),
                          ),
                    ],
                  ),
                )
              else
                InkWell(
                  onTap: () => setState(() => _addCurrency = true),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Text(
                      '+ Add a currency',
                      style: ui(13, 800, color: c.muted),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Note(
            'The default is used everywhere unless a group overrides it.',
          ),
          const SizedBox(height: 18),

          const SectionLabel('Friends'),
          const SizedBox(height: 8),
          _ListCard(
            children: [
              for (final f in app.friends)
                _RowPad(
                  child: CompactRow(
                    child: Row(
                      children: [
                        Avatar(
                          name: app.nameOf(f.id),
                          color: Color(f.color),
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            app.nameOf(f.id),
                            style: ui(14, 800, color: c.ink),
                          ),
                        ),
                        if (f.isYou)
                          Capped(
                            child: Text(
                              'that is you',
                              style: ui(12, 600, color: c.muted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          _RemoveButton(
                            semanticLabel: 'Remove ${f.name}',
                            onTap: () => app.removeFriend(f.id),
                          ),
                      ],
                    ),
                  ),
                ),
              _RowPad(
                divider: false,
                child: CompactRow(
                  child: Row(
                    children: [
                      Expanded(
                        child: BillField(
                          controller: _newFriend,
                          hint: 'Add a friend',
                          fill: c.bg,
                          fontSize: 13.5,
                          weight: 700,
                          radius: R.tight,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          onSubmitted: (_) => _addFriend(app),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Capped(
                        child: SolidButton(
                          label: 'Add',
                          fontSize: 12.5,
                          radius: R.tight,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          onPressed: () => _addFriend(app),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          const SectionLabel('Security'),
          const SizedBox(height: 8),
          BillCard(
            radius: R.small,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Protect with a PIN',
                        style: ui(14, 800, color: c.ink),
                      ),
                      Note(
                        app.settings.pinOn
                            ? 'PIN asked whenever the app opens.'
                            : 'Off. Anyone with the phone can open Split the Bill.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Toggle(
                  on: app.settings.pinOn,
                  onChanged: (v) {
                    if (v && !app.settings.hasPin) {
                      setState(() => _changingPin = true);
                    } else {
                      app.setPinOn(v);
                    }
                  },
                ),
              ],
            ),
          ),
          if (app.settings.pinOn || _changingPin) ...[
            const SizedBox(height: 8),
            BillCard(
              radius: R.small,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: _changingPin
                  ? Row(
                      children: [
                        Expanded(
                          child: BillField(
                            controller: _pin,
                            hint: '4 digits',
                            maxLength: 4,
                            obscure: true,
                            monoFont: true,
                            fontSize: 14,
                            weight: 700,
                            radius: R.tight,
                            fill: c.bg,
                            keyboardType: TextInputType.number,
                            // The keypad that unlocks the app has only
                            // digits on it. A PIN with a letter in it -
                            // pasted, or typed on a keyboard that ignores
                            // the numeric hint - could be set and then never
                            // entered again, and with backups off there is
                            // no way back into the receipts at all.
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SolidButton(
                          label: 'Save',
                          fontSize: 12.5,
                          radius: R.tight,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          onPressed: () {
                            if (RegExp(r'^\d{4}$').hasMatch(_pin.text)) {
                              app.setPin(_pin.text);
                              _pin.clear();
                              setState(() => _changingPin = false);
                            }
                          },
                        ),
                      ],
                    )
                  : InkWell(
                      onTap: () => setState(() => _changingPin = true),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Change PIN',
                              style: ui(14, 800, color: c.ink),
                            ),
                          ),
                          for (var i = 0; i < 4; i++)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 5),
                              decoration: BoxDecoration(
                                color: c.muted,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
          const SizedBox(height: 18),

          const SectionLabel('Data'),
          const SizedBox(height: 8),
          TwoTapButton(
            label: 'Clear all data',
            confirmLabel: 'Tap again to erase everything',
            onConfirmed: app.clearAllData,
          ),
          const SizedBox(height: 8),
          Note(
            persistenceAvailable
                ? 'Deletes every group, receipt and friend from this phone. '
                      'There is no cloud copy to restore.'
                : 'This is the browser preview, so nothing is saved between '
                      'visits. On a phone everything is stored on the device, '
                      'and there is no cloud copy to restore.',
          ),
          const SizedBox(height: 22),
          Center(
            child: Text(
              'Split the Bill $appVersion',
              style: ui(11.5, 700, color: c.muted),
            ),
          ),
        ],
      ),
    );
  }

  static String _currencyName(String sym) => currencyCatalogue
      .firstWhere((e) => e.$1 == sym, orElse: () => (sym, 'Currency'))
      .$2;
}

/// A card whose children are separated by hairlines.
class _ListCard extends StatelessWidget {
  final List<Widget> children;
  const _ListCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(R.small),
        border: Border.all(color: c.line, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _RowPad extends StatelessWidget {
  final Widget child;
  final bool divider;
  const _RowPad({required this.child, this.divider = true});

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
            )
          : null,
      child: child,
    );
  }
}

/// The round grey ✕ used to remove a currency or a friend.
class _RemoveButton extends StatelessWidget {
  final VoidCallback onTap;
  final String semanticLabel;
  const _RemoveButton({required this.onTap, required this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
          child: Icon(Icons.close, size: 14, color: c.muted),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Material(
      color: selected ? c.segBg : Colors.transparent,
      borderRadius: BorderRadius.circular(R.tight),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.tight),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(9),
          child: Text(
            label,
            style: ui(13, 800, color: selected ? c.segFg : c.muted),
          ),
        ),
      ),
    );
  }
}

/// The 46x26 pill switch from the prototype.
class _Toggle extends StatelessWidget {
  final bool on;
  final ValueChanged<bool> onChanged;
  const _Toggle({required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Semantics(
      toggled: on,
      button: true,
      label: 'PIN lock',
      child: GestureDetector(
        onTap: () => onChanged(!on),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 46,
          height: 26,
          padding: const EdgeInsets.all(3),
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          decoration: BoxDecoration(
            color: on ? Brand.green : c.chip,
            borderRadius: BorderRadius.circular(R.pill),
          ),
          child: Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x4D000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
