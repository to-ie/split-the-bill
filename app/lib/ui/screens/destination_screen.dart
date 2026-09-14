import 'package:flutter/material.dart';

import '../../app.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/screen_scaffold.dart';
import 'people_screen.dart';

/// Step 1 of 6.
class DestinationScreen extends StatefulWidget {
  const DestinationScreen({super.key});

  @override
  State<DestinationScreen> createState() => _DestinationScreenState();
}

class _DestinationScreenState extends State<DestinationScreen> {
  bool _newGroup = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _next() => Navigator.of(context).push(fadeUpRoute(const PeopleScreen()));

  void _create(AppState app) {
    if (_name.text.trim().isEmpty) return;
    final g = app.createGroup(_name.text);
    app.setDestination(g.id);
    setState(() => _newGroup = false);
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);
    final groups = app.groupsForDestination;

    return ScreenScaffold(
      title: 'Where does this bill go?',
      subtitle: 'Step 1 of 6',
      discardable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (groups.isNotEmpty) ...[
            const SectionLabel('Add to a group'),
            const SizedBox(height: 10),
            for (final g in groups) ...[
              BillCard(
                onTap: () {
                  app.setDestination(g.id);
                  _next();
                },
                child: Row(
                  children: [
                    MonogramTile(
                      text: _initials(g.name),
                      background: c.okBg,
                      foreground: c.okFg,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.name,
                            style: ui(15, 800, color: c.ink),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${g.receipts.length} '
                            '${g.receipts.length == 1 ? 'receipt' : 'receipts'} so far',
                            style: ui(12.5, 600, color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    const Chevron(),
                  ],
                ),
              ),
              const SizedBox(height: R.gap),
            ],
          ],

          if (_newGroup)
            Row(
              children: [
                Expanded(
                  child: BillField(
                    controller: _name,
                    hint: 'Group name, e.g. Lisbon trip',
                    autofocus: true,
                    fontSize: 14,
                    weight: 700,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    radius: 11,
                    onSubmitted: (_) => _create(app),
                  ),
                ),
                const SizedBox(width: 8),
                SolidButton(label: 'Create', onPressed: () => _create(app)),
              ],
            )
          else
            DashedButton(
              label: '+ Start a new group',
              onPressed: () => setState(() => _newGroup = true),
            ),

          const SizedBox(height: 20),
          const SectionLabel('Or keep it separate'),
          const SizedBox(height: 10),
          BillCard(
            onTap: () {
              app.setDestination(null);
              _next();
            },
            child: Row(
              children: [
                MonogramTile(
                  text: '1',
                  background: c.chip,
                  foreground: c.muted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('One-off split', style: ui(15, 800, color: c.ink)),
                      Text(
                        'Not part of a group',
                        style: ui(12.5, 600, color: c.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
  }
}
