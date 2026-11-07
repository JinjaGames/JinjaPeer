import 'dart:io';

import 'package:flutter/material.dart';

/// Design tokens for the "liquid glass" look. Accessed via `context.jp`.
@immutable
class JP extends ThemeExtension<JP> {
  const JP({
    required this.isDark,
    required this.bgTop,
    required this.bgBottom,
    required this.blobs,
    required this.glass,
    required this.glassStrong,
    required this.glassBorder,
    required this.glassHighlight,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accent2,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shadow,
    required this.divider,
  });

  final bool isDark;
  final Color bgTop;
  final Color bgBottom;
  final List<Color> blobs;
  final Color glass;
  final Color glassStrong;
  final Color glassBorder;
  final Color glassHighlight;
  final Color text;
  final Color textMuted;
  final Color textFaint;
  final Color accent;
  final Color accent2;
  final Color success;
  final Color warning;
  final Color danger;
  final Color shadow;
  final Color divider;

  LinearGradient get accentGradient => LinearGradient(
        colors: [accent, accent2],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static const dark = JP(
    isDark: true,
    bgTop: Color(0xFF0A0E1A),
    bgBottom: Color(0xFF0E1324),
    blobs: [Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFF06B6D4), Color(0xFFDB2777)],
    glass: Color(0x14FFFFFF),
    glassStrong: Color(0x22FFFFFF),
    glassBorder: Color(0x26FFFFFF),
    glassHighlight: Color(0x33FFFFFF),
    text: Color(0xFFF1F5F9),
    textMuted: Color(0xFFA5B0C4),
    textFaint: Color(0xFF6B768C),
    accent: Color(0xFF38BDF8),
    accent2: Color(0xFFA78BFA),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    shadow: Color(0x66000000),
    divider: Color(0x1AFFFFFF),
  );

  static const light = JP(
    isDark: false,
    bgTop: Color(0xFFEFF3FF),
    bgBottom: Color(0xFFF7F3FF),
    blobs: [Color(0xFF93C5FD), Color(0xFFC4B5FD), Color(0xFF67E8F9), Color(0xFFF9A8D4)],
    glass: Color(0x8CFFFFFF),
    glassStrong: Color(0xB8FFFFFF),
    glassBorder: Color(0xCCFFFFFF),
    glassHighlight: Color(0xFFFFFFFF),
    text: Color(0xFF0F172A),
    textMuted: Color(0xFF475569),
    textFaint: Color(0xFF8A94A8),
    accent: Color(0xFF0284C7),
    accent2: Color(0xFF7C3AED),
    success: Color(0xFF059669),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
    shadow: Color(0x1F1E293B),
    divider: Color(0x14000000),
  );

  @override
  JP copyWith() => this;

  @override
  JP lerp(ThemeExtension<JP>? other, double t) {
    if (other is! JP) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return JP(
      isDark: t < 0.5 ? isDark : other.isDark,
      bgTop: l(bgTop, other.bgTop),
      bgBottom: l(bgBottom, other.bgBottom),
      blobs: [for (var i = 0; i < blobs.length; i++) l(blobs[i], other.blobs[i])],
      glass: l(glass, other.glass),
      glassStrong: l(glassStrong, other.glassStrong),
      glassBorder: l(glassBorder, other.glassBorder),
      glassHighlight: l(glassHighlight, other.glassHighlight),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      textFaint: l(textFaint, other.textFaint),
      accent: l(accent, other.accent),
      accent2: l(accent2, other.accent2),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      shadow: l(shadow, other.shadow),
      divider: l(divider, other.divider),
    );
  }
}

extension JPContext on BuildContext {
  JP get jp => Theme.of(this).extension<JP>()!;
  TextTheme get tt => Theme.of(this).textTheme;
}

/// Spacing scale (4pt grid).
abstract final class S {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Corner radius scale.
abstract final class R {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;
}

const kMono = 'Consolas';

String? get _platformFont {
  if (Platform.isWindows) return 'Segoe UI Variable Text';
  return null;
}

ThemeData buildTheme(JP jp) {
  final brightness = jp.isDark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: jp.accent,
    brightness: brightness,
    primary: jp.accent,
    secondary: jp.accent2,
    error: jp.danger,
    surface: jp.bgBottom,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: _platformFont,
    fontFamilyFallback: const ['Segoe UI', 'Roboto', 'SF Pro Text', 'Noto Sans'],
    scaffoldBackgroundColor: jp.bgTop,
    extensions: [jp],
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
  );
  final t = base.textTheme.apply(bodyColor: jp.text, displayColor: jp.text);
  return base.copyWith(
    textTheme: t.copyWith(
      displaySmall: t.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
      headlineMedium: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.6, fontSize: 28),
      headlineSmall: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4, fontSize: 22),
      titleLarge: t.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2, fontSize: 18),
      titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
      titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 15, height: 1.45),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 13.5, height: 1.45, color: jp.text),
      bodySmall: t.bodySmall?.copyWith(fontSize: 12, height: 1.4, color: jp.textMuted),
      labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600, fontSize: 13.5),
      labelMedium: t.labelMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
      labelSmall: t.labelSmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 11, letterSpacing: 0.4),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: jp.isDark ? const Color(0xF01B2236) : const Color(0xF0FFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: jp.glassBorder),
        boxShadow: [BoxShadow(color: jp.shadow, blurRadius: 16, offset: const Offset(0, 6))],
      ),
      textStyle: TextStyle(color: jp.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 450),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: jp.accent,
      selectionColor: jp.accent.withValues(alpha: 0.3),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(jp.textFaint.withValues(alpha: 0.45)),
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(8),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : jp.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected) ? jp.accent : jp.glassStrong),
    ),
    dividerTheme: DividerThemeData(color: jp.divider, thickness: 1, space: 1),
    popupMenuTheme: PopupMenuThemeData(
      color: jp.isDark ? const Color(0xFF161C2E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.md),
        side: BorderSide(color: jp.glassBorder),
      ),
      textStyle: TextStyle(color: jp.text, fontSize: 13.5),
      elevation: 12,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: jp.isDark ? const Color(0x0FFFFFFF) : const Color(0x99FFFFFF),
      hintStyle: TextStyle(color: jp.textFaint),
      labelStyle: TextStyle(color: jp.textMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: BorderSide(color: jp.glassBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: BorderSide(color: jp.glassBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: BorderSide(color: jp.accent, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: BorderSide(color: jp.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(R.md),
        borderSide: BorderSide(color: jp.danger, width: 1.4),
      ),
    ),
  );
}

/// Stable, pleasant avatar gradient for a seed.
List<Color> avatarColors(int seed) {
  const palettes = [
    [Color(0xFF38BDF8), Color(0xFF6366F1)],
    [Color(0xFFF472B6), Color(0xFFA855F7)],
    [Color(0xFF34D399), Color(0xFF0EA5E9)],
    [Color(0xFFFBBF24), Color(0xFFF97316)],
    [Color(0xFF818CF8), Color(0xFFC084FC)],
    [Color(0xFF2DD4BF), Color(0xFF22C55E)],
    [Color(0xFFFB7185), Color(0xFFF59E0B)],
    [Color(0xFF60A5FA), Color(0xFF2DD4BF)],
  ];
  return palettes[seed.abs() % palettes.length];
}

/// Stable avatar seed from an identity key or name.
int seedOf(String s) => s.codeUnits.fold(0, (a, b) => a + b);
