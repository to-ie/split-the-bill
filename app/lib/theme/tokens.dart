import 'package:flutter/material.dart';

/// Design tokens, taken value for value from the prototype's inline styles.
/// Every screen reads colours off [BillColors] and never hard-codes one.
@immutable
class BillColors extends ThemeExtension<BillColors> {
  final Color bg;
  final Color card;

  /// Solid hairlines and card borders.
  final Color line;

  /// Dashed rules, input borders, dashed buttons.
  final Color line2;

  final Color ink;
  final Color muted;
  final Color chip;

  /// Positive tint: privacy chip, "Mark paid", group chips, settled badge.
  final Color okBg;
  final Color okFg;

  /// The "solid" button pair (Done, Add, Create, Copy, segmented control).
  /// Inverts between themes.
  final Color segBg;
  final Color segFg;

  /// Amber warning.
  final Color amberBg;
  final Color amberLine;

  /// Error.
  final Color errorTint;
  final Color errorFg;

  /// Home tile tint for a group with only one person in it.
  final Color soloBg;
  final Color soloFg;

  const BillColors({
    required this.bg,
    required this.card,
    required this.line,
    required this.line2,
    required this.ink,
    required this.muted,
    required this.chip,
    required this.okBg,
    required this.okFg,
    required this.segBg,
    required this.segFg,
    required this.amberBg,
    required this.amberLine,
    required this.errorTint,
    required this.errorFg,
    required this.soloBg,
    required this.soloFg,
  });

  static const light = BillColors(
    bg: Color(0xFFF7F4EE),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFE5E0D2),
    line2: Color(0xFFD8D2C2),
    ink: Color(0xFF1E2749),
    muted: Color(0xFF8B8677),
    chip: Color(0xFFEDE9DE),
    okBg: Color(0xFFE4F4EC),
    okFg: Color(0xFF0B845E),
    segBg: Color(0xFF1E2749),
    segFg: Color(0xFFFFFFFF),
    amberBg: Color(0xFFFCF8EC),
    amberLine: Color(0xFFEFE4C3),
    errorTint: Color(0xFFFBEAE5),
    errorFg: Color(0xFFA93A26),
    soloBg: Color(0xFFFCF3DE),
    soloFg: Color(0xFFA97A10),
  );

  static const dark = BillColors(
    bg: Color(0xFF14181F),
    card: Color(0xFF1E242E),
    line: Color(0xFF2B3240),
    line2: Color(0xFF39414F),
    ink: Color(0xFFEFECE2),
    muted: Color(0xFF98948A),
    chip: Color(0xFF2A303C),
    okBg: Color(0xFF143528),
    okFg: Color(0xFF4CCB9A),
    segBg: Color(0xFFEFECE2),
    segFg: Color(0xFF14181F),
    amberBg: Color(0xFF2C2716),
    amberLine: Color(0xFF4A4128),
    errorTint: Color(0xFF3A1D16),
    errorFg: Color(0xFFE8836C),
    soloBg: Color(0xFF3A3315),
    soloFg: Color(0xFFD9B44A),
  );

  @override
  BillColors copyWith() => this;

  @override
  BillColors lerp(ThemeExtension<BillColors>? other, double t) {
    if (other is! BillColors) return this;
    return t < 0.5 ? this : other;
  }
}

/// Fixed colours that do not follow the theme.
class Brand {
  /// The green. Identical in both themes.
  static const green = Color(0xFF10A374);

  /// The 2px hard shadow under every primary button.
  static const greenShadow = Color(0xFF0B845E);

  /// The navy hero panel. Navy in dark mode too.
  static const navy = Color(0xFF1E2749);

  /// Viewfinder body and the scanline.
  static const viewfinder = Color(0xFF1C222C);
  static const scanline = Color(0xFF2EE6A8);

  static const error = Color(0xFFC44536);
  static const amberIcon = Color(0xFFC89B2A);
}

/// Shape and spacing.
class R {
  /// Cards, primary buttons, hero panels.
  static const card = 16.0;

  /// Smaller cards: members, receipts rows, banners, chip buttons.
  static const small = 14.0;

  /// Inputs.
  static const input = 12.0;

  /// Inline inputs inside the receipt card.
  static const tight = 9.0;

  static const pill = 99.0;

  /// Gap between stacked cards.
  static const gap = 10.0;

  /// Horizontal padding of a screen body.
  static const pad = 20.0;
}

/// Nunito and Roboto Mono ship as variable fonts, so the weight axis has to be
/// set explicitly. Setting fontWeight alone leaves every string at 400 and
/// quietly loses the whole typographic design.
TextStyle ui(
  double size,
  int weight, {
  Color? color,
  double? letterSpacing,
  double? height,
  TextDecoration? decoration,
}) => TextStyle(
  fontFamily: 'Nunito',
  fontSize: size,
  fontWeight: FontWeight.values[(weight ~/ 100) - 1],
  fontVariations: [FontVariation('wght', weight.toDouble())],
  color: color,
  letterSpacing: letterSpacing,
  height: height,
  decoration: decoration,
  decorationColor: color,
);

TextStyle mono(
  double size,
  int weight, {
  Color? color,
  double? letterSpacing,
  double? height,
  TextDecoration? decoration,
}) => TextStyle(
  fontFamily: 'RobotoMono',
  fontSize: size,
  fontWeight: FontWeight.values[(weight ~/ 100) - 1],
  fontVariations: [FontVariation('wght', weight.toDouble())],
  color: color,
  letterSpacing: letterSpacing,
  height: height,
  decoration: decoration,
  decorationColor: color,
);

/// Section header: 12px/900, 0.8 letter-spacing, uppercase, muted.
TextStyle sectionHeader(Color color) =>
    ui(12, 900, color: color, letterSpacing: 0.8);

/// The line under a screen title: 11px/900, 0.6 letter-spacing, uppercase.
TextStyle screenSubtitle(Color color) =>
    ui(11, 800, color: color, letterSpacing: 0.6);
