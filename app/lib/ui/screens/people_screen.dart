import 'package:flutter/material.dart';

import '../../app.dart';
import '../../state/app_state.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/screen_scaffold.dart';
import 'scan_screen.dart';

/// Step 2 of 6. There is no "just me" mode: the app always splits.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  bool _adding = false;
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _add(AppState app) {
    if (_name.text.trim().isEmpty) {
      setState(() => _adding = false);
      return;
    }
    final f = app.addFriend(_name.text);
    app.toggleParty(f.id);
    _name.clear();
    setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);
    final draft = app.draft;
    if (draft == null) return const SizedBox.shrink();

    final party = draft.receipt.party;
    final group = app.groupById(draft.groupId);
    final destTag = group == null ? ' · one-off' : ' · ${group.name}';

    return ScreenScaffold(
      title: "Who's splitting?",
      subtitle: 'Step 2 of 6$destTag',
      discardable: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Friends'),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: R.gap,
            crossAxisSpacing: R.gap,
            childAspectRatio: 2.55,
            children: [
              for (final f in app.friends)
                _FriendChip(
                  name: app.nameOf(f.id),
                  color: Color(f.color),
                  selected: party.contains(f.id),
                  locked: f.isYou,
                  onTap: () => app.toggleParty(f.id),
                ),
            ],
          ),
          const SizedBox(height: R.gap),
          if (_adding)
            Row(
              children: [
                Expanded(
                  child: BillField(
                    controller: _name,
                    hint: "Friend's name",
                    autofocus: true,
                    fontSize: 14,
                    weight: 700,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    radius: 11,
                    onSubmitted: (_) => _add(app),
                  ),
                ),
                const SizedBox(width: 8),
                SolidButton(label: 'Add', onPressed: () => _add(app)),
              ],
            )
          else
            DashedButton(
              label: '+ Add someone new',
              filled: true,
              onPressed: () => setState(() => _adding = true),
            ),
          const SizedBox(height: 16),
          Text(
            party.length < 2
                ? 'Pick at least one other person.'
                : '${party.length} splitting, including you.',
            style: ui(13.5, 700, color: c.muted),
          ),
        ],
      ),
      footer: PrimaryButton(
        label: 'Next · scan the bill',
        onPressed: party.length < 2
            ? null
            : () => Navigator.of(context).push(fadeUpRoute(const ScanScreen())),
      ),
    );
  }
}

/// A horizontal chip: avatar on the left, name beside it, tick badge floating
/// off the top-right corner.
class _FriendChip extends StatelessWidget {
  final String name;
  final Color color;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  const _FriendChip({
    required this.name,
    required this.color,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: GestureDetector(
        onTap: locked ? null : onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(R.small),
                border: Border.all(
                  color: selected ? Brand.green : c.line,
                  width: selected ? 2 : 1.5,
                ),
              ),
              child: Row(
                children: [
                  Avatar(name: name, color: color, size: 34),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ui(14.5, 800, color: c.ink),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Positioned(
                top: -7,
                right: -7,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Brand.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.bg, width: 2),
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
