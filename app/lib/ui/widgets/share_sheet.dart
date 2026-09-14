import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Share is copy-to-clipboard, nothing more. No messaging SDKs, no network:
/// the user pastes the text wherever they like.
Future<void> showShareSheet(BuildContext context, String title, String text) {
  final c = colors(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: c.card,
    barrierColor: const Color(0x800A0E18),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _ShareSheet(title: title, text: text),
  );
}

class _ShareSheet extends StatefulWidget {
  final String title;
  final String text;
  const _ShareSheet({required this.title, required this.text});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        R.pad,
        14,
        R.pad,
        MediaQuery.of(context).viewInsets.bottom + 26,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(widget.title, style: ui(18, 900, color: c.ink)),
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(maxHeight: 190),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(R.small),
              border: Border.all(color: c.line, width: 1.5),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                widget.text,
                style: mono(11.5, 400, color: c.ink, height: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Material(
            color: c.segBg,
            borderRadius: BorderRadius.circular(R.small),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.small),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: widget.text));
                if (context.mounted) setState(() => _copied = true);
              },
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.all(14),
                child: Text(
                  _copied ? 'Copied' : 'Copy to clipboard',
                  style: ui(15, 900, color: c.segFg),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
