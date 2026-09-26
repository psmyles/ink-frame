import 'package:flutter/material.dart';

/// Calm, photo-first look (app-flow §8): paper white / charcoal, one Spectra 6 red
/// accent tuned for contrast, muted status colours from the same palette.
class InkColors extends ThemeExtension<InkColors> {
  const InkColors({required this.ok, required this.warning});

  final Color ok;
  final Color warning;

  static const light = InkColors(ok: Color(0xFF35563A), warning: Color(0xFF7A5C00));
  static const dark = InkColors(ok: Color(0xFF7FB287), warning: Color(0xFFD9B84A));

  @override
  InkColors copyWith({Color? ok, Color? warning}) => InkColors(ok: ok ?? this.ok, warning: warning ?? this.warning);

  @override
  InkColors lerp(InkColors? other, double t) => other == null
      ? this
      : InkColors(ok: Color.lerp(ok, other.ok, t)!, warning: Color.lerp(warning, other.warning, t)!);
}

abstract final class InkTheme {
  static ThemeData light() => _build(
        const ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFFA8322D),
          onPrimary: Colors.white,
          secondary: Color(0xFF233F8E),
          onSecondary: Colors.white,
          // Selected chips and segments: a warm neutral, so red stays the only accent.
          secondaryContainer: Color(0xFFE9DFD9),
          onSecondaryContainer: Color(0xFF22211F),
          error: Color(0xFFB3261E),
          onError: Colors.white,
          surface: Color(0xFFF7F5F0),
          onSurface: Color(0xFF22211F),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Color(0xFFF2EFE9),
          surfaceContainer: Color(0xFFEDEAE3),
          surfaceContainerHigh: Color(0xFFE7E3DB),
          surfaceContainerHighest: Color(0xFFE1DDD4),
          onSurfaceVariant: Color(0xFF6B6862),
          outline: Color(0xFFB9B4AA),
          outlineVariant: Color(0xFFE4E0D8),
        ),
        InkColors.light,
      );

  static ThemeData dark() => _build(
        const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFFE0574F),
          onPrimary: Color(0xFF141414),
          secondary: Color(0xFF9DB0E8),
          onSecondary: Color(0xFF141414),
          secondaryContainer: Color(0xFF3A322E),
          onSecondaryContainer: Color(0xFFEFECE6),
          error: Color(0xFFF2B8B5),
          onError: Color(0xFF601410),
          surface: Color(0xFF141414),
          onSurface: Color(0xFFEFECE6),
          surfaceContainerLowest: Color(0xFF0F0F0F),
          surfaceContainerLow: Color(0xFF1C1B19),
          surfaceContainer: Color(0xFF211F1D),
          surfaceContainerHigh: Color(0xFF292724),
          surfaceContainerHighest: Color(0xFF32302C),
          onSurfaceVariant: Color(0xFFA8A49C),
          outline: Color(0xFF5A5751),
          outlineVariant: Color(0xFF3A3834),
        ),
        InkColors.dark,
      );

  static ThemeData _build(ColorScheme scheme, InkColors ink) {
    final base = ThemeData(colorScheme: scheme, useMaterial3: true);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    const buttonSize = Size(64, 52);
    final buttonText = base.textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600);
    return base.copyWith(
      extensions: [ink],
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // ThemeData's text styles carry no sizes until Theme.of localizes them.
        titleTextStyle: base.textTheme.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w600, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: buttonSize, shape: shape, textStyle: buttonText),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: shape,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          textStyle: buttonText,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    );
  }
}

extension InkThemeX on BuildContext {
  InkColors get ink => Theme.of(this).extension<InkColors>()!;
}
