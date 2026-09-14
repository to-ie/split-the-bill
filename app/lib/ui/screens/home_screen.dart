import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../model/models.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import 'archived_screen.dart';
import 'destination_screen.dart';
import 'group_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);
    final groups = app.visibleGroups;
    final archived = app.archivedGroups;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        // "Split a new bill" is the only thing on this screen anyone came
        // here to do, so it is pinned to the bottom of the viewport and
        // everything else scrolls behind it. It used to sit at the end of one
        // long scrolling column, which put it off the bottom of the screen as
        // soon as there were three groups and an archive row.
        child: Column(
          children: [
            Expanded(
              // The logo sits in the top half and the groups are pushed down
              // to meet the button. IntrinsicHeight is what lets the Spacer do
              // that inside a scroll view: without it the column has unbounded
              // height and the flex child has nothing to expand into.
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: RoundIconButton(
                                semanticLabel: 'Settings',
                                onTap: () => Navigator.of(context)
                                    .push(fadeUpRoute(const SettingsScreen())),
                                icon: Icon(
                                  Icons.settings_outlined,
                                  size: 21,
                                  color: c.muted,
                                ),
                              ),
                            ),
                            const Center(child: _Logo()),
                            const SizedBox(height: 14),
                            Text(
                              'Split the bill in seconds.',
                              textAlign: TextAlign.center,
                              style: ui(24, 900, color: c.ink, height: 1.2),
                            ),
                            const SizedBox(height: 12),
                            const Center(child: _PrivacyChip()),

                            // Takes up whatever is left when there are only a
                            // group or two, and collapses to nothing when the
                            // list is long enough to scroll.
                            const Spacer(),
                            const SizedBox(height: 20),

                            if (groups.isEmpty)
                              DashedBox(
                                child: Text(
                                  'Nothing yet. Scan your first bill.',
                                  textAlign: TextAlign.center,
                                  style: ui(13.5, 700, color: c.muted),
                                ),
                              )
                            else
                              for (final g in groups) ...[
                                _GroupRow(groupId: g.id),
                                const SizedBox(height: R.gap),
                              ],

                            if (archived.isNotEmpty)
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => Navigator.of(
                                    context,
                                  ).push(fadeUpRoute(const ArchivedScreen())),
                                  borderRadius: BorderRadius.circular(R.small),
                                  child: Padding(
                                    padding: const EdgeInsets.all(11),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.inventory_2_outlined,
                                          size: 15,
                                          color: c.muted,
                                        ),
                                        const SizedBox(width: 8),
                                        // Flexible, because at large system
                                        // text this label is wider than a
                                        // small phone and used to overflow.
                                        Flexible(
                                          child: Text(
                                            'Archived groups '
                                            '(${archived.length})',
                                            style: ui(13, 800, color: c.muted),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 26),
              child: PrimaryButton(
                label: 'Split a new bill',
                onPressed: () {
                  AppScope.read(context).startFlow();
                  Navigator.of(context)
                      .push(fadeUpRoute(const DestinationScreen()));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyChip extends StatelessWidget {
  const _PrivacyChip();

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.okBg,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 5),
            decoration: const BoxDecoration(
              color: Brand.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              'On-device only · receipts never leave your phone',
              style: ui(11.5, 800, color: c.okFg),
            ),
          ),
        ],
      ),
    );
  }
}

/// The logo with the drop shadow the handoff specifies.
///
/// A BoxShadow would paint a rectangle behind the artwork, ignoring its
/// transparency. Blurring a tinted copy of the image gives a shadow in the
/// shape of the logo, which is what `filter: drop-shadow` does in the
/// prototype.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    const image = Image(
      image: AssetImage('assets/images/logo.png'),
      width: 132,
      semanticLabel: 'Split the Bill',
    );

    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.translate(
          offset: const Offset(0, 8),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
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

class _GroupRow extends StatelessWidget {
  final String groupId;
  const _GroupRow({required this.groupId});

  /// "Lisbon trip" -> "LT", "Coffee" -> "C".
  static String initials(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);
    final g = app.groupById(groupId)!;
    final people = g.members.length;
    final multi = people > 1;
    final outstanding = app.groupOutstandingCents(g);

    return BillCard(
      onTap: () =>
          Navigator.of(context)
              .push(fadeUpRoute(GroupScreen(groupId: groupId))),
      child: CompactRow(
        child: Row(
          children: [
            MonogramTile(
              text: initials(g.name),
              background: multi ? c.okBg : c.soloBg,
              foreground: multi ? c.okFg : c.soloFg,
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
                    _sub(g, people),
                    style: ui(12.5, 600, color: c.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // What is still to be handed over, not what the group spent. A
            // group everybody has settled up should not keep showing a large
            // number as though money were outstanding.
            // How much room the badge may take, leaving enough beside it
            // for the group's name. It is worked out from the screen width
            // rather than the row's, because this card sits inside an
            // IntrinsicHeight and a LayoutBuilder cannot be measured there.
            //
            // At ordinary text sizes the badge is nowhere near this wide
            // and nothing happens. At the largest system text on the
            // narrowest phone it came to 176 points and squeezed the name
            // to nothing.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (MediaQuery.sizeOf(context).width - 206).clamp(
                  64.0,
                  300.0,
                ),
              ),
              child: outstanding == 0
                  ? const TintPill(label: 'All square', fontSize: 11.5)
                  : Text(
                      app.moneyCents(outstanding, groupId: groupId),
                      style: mono(14, 700, color: c.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const Chevron(),
          ],
        ),
      ),
    );
  }

  static String _sub(Group g, int people) {
    final n = g.receipts.length;
    final receipts = '$n ${n == 1 ? 'receipt' : 'receipts'}';
    return '$receipts · ${people > 1 ? '$people people' : 'just you'}';
  }
}
