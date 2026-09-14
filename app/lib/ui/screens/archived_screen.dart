import 'package:flutter/material.dart';

import '../../app.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/screen_scaffold.dart';
import 'group_screen.dart';

class ArchivedScreen extends StatelessWidget {
  const ArchivedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final c = colors(context);
    final archived = app.archivedGroups;

    return ScreenScaffold(
      title: 'Archived groups',
      subtitle: 'Out of the way, not deleted',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (archived.isEmpty)
            DashedBox(
              child: Text(
                'No archived groups.',
                textAlign: TextAlign.center,
                style: ui(13.5, 700, color: c.muted),
              ),
            ),
          for (final g in archived) ...[
            BillCard(
              child: CompactRow(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            Navigator.of(context)
                                .push(fadeUpRoute(GroupScreen(groupId: g.id))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(g.name, style: ui(15, 800, color: c.ink)),
                            Text(
                              '${g.receipts.length} '
                              '${g.receipts.length == 1 ? 'receipt' : 'receipts'}',
                              style: ui(12.5, 600, color: c.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Capped(
                      fraction: 0.3,
                      child: Text(
                        app.moneyCents(
                          app.groupOutstandingCents(g),
                          groupId: g.id,
                        ),
                        style: mono(14, 700, color: c.ink),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Capped(
                      fraction: 0.35,
                      child: TintPill(
                        label: 'Restore',
                        onTap: () => app.setArchived(g.id, false),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: R.gap),
          ],
        ],
      ),
    );
  }
}
