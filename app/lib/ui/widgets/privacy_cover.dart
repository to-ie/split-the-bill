import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Drawn over everything while the app is not frontmost, so the task
/// switcher's thumbnail shows this rather than somebody's receipts.
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});

  @override
  Widget build(BuildContext context) {
    final c = colors(context);
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: ColoredBox(
          color: c.bg,
          child: const Center(
            child: Image(
              image: AssetImage('assets/images/logo.png'),
              width: 108,
              semanticLabel: 'Split the Bill',
            ),
          ),
        ),
      ),
    );
  }
}
