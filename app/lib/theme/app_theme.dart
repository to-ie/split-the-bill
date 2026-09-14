import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTheme(bool dark) {
  final c = dark ? BillColors.dark : BillColors.light;
  final base = dark ? ThemeData.dark() : ThemeData.light();

  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Brand.green,
      brightness: dark ? Brightness.dark : Brightness.light,
      surface: c.card,
      primary: Brand.green,
      error: Brand.error,
    ),
    extensions: [c],
    textTheme: base.textTheme.apply(fontFamily: 'Nunito'),
    splashFactory: InkRipple.splashFactory,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Brand.green,
      selectionColor: Brand.green.withValues(alpha: 0.25),
      selectionHandleColor: Brand.green,
    ),
  );
}

/// Shorthand used by every widget in the app.
BillColors colors(BuildContext context) =>
    Theme.of(context).extension<BillColors>()!;
