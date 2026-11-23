import 'package:material_ui/material_ui.dart';

/// Design tokens converted directly from SrolanhCity UX/UI Design Board
/// (khmer-response-studio.lovable.app).
abstract final class AppColors {
  // Surfaces & neutrals
  static const paper = Color(0xFFFCF9F3); // Warm ivory paper (--background)
  static const card = Colors.white;
  static const ink = Color(0xFF042126); // Deep Mekong ink (--foreground)
  static const muted = Color(0xFF596D71); // --muted-foreground
  static const mutedSurface = Color(0xFFF3F0E9); // --muted
  static const secondarySurface = Color(0xFFF3EEE3); // --secondary
  static const border = Color(0xFFE5E1D9); // --border
  static const device = Color(0xFF132225); // --device (dark viewfinder)

  // Brand Primary — Mekong Teal
  static const teal = Color(0xFF006657); // --primary
  static const tealDark = Color(0xFF004043); // --gradient-hero end
  static const tealSoft = Color(0xFFD3F3EC); // --primary-soft

  // Brand Accent — Saffron Gold
  static const saffron = Color(0xFFF5AE39); // --accent
  static const saffronInk = Color(0xFF331B06); // --accent-foreground
  static const saffronSoft = Color(0xFFFFECC9); // --accent-soft
  static const saffronGradStart = Color(0xFFF4C352);
  static const saffronGradEnd = Color(0xFFF28F29);

  // Semantic
  static const success = Color(0xFF399D57); // --success
  static const successSoft = Color(0xFFDCF7E1); // --success-soft
  static const danger = Color(0xFFD7352D); // --destructive
  static const dangerSoft = Color(0xFFFFE6E2); // --destructive-soft

  // Gradients
  static const heroGradient = LinearGradient(
    begin: Alignment(-0.4, -1.0),
    end: Alignment(0.4, 1.0),
    colors: [teal, tealDark],
  );

  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [saffronGradStart, saffronGradEnd],
  );

  // Shadows
  static final List<BoxShadow> cardShadow = [
    BoxShadow(
      color: ink.withValues(alpha: 0.05),
      blurRadius: 3,
      offset: const Offset(0, 1),
    ),
    BoxShadow(
      color: ink.withValues(alpha: 0.10),
      blurRadius: 20,
      spreadRadius: -8,
      offset: const Offset(0, 8),
    ),
  ];

  static final List<BoxShadow> fabShadow = [
    BoxShadow(
      color: teal.withValues(alpha: 0.42),
      blurRadius: 20,
      spreadRadius: -4,
      offset: const Offset(0, 10),
    ),
  ];

  /// Ministry Action Level 1–5 priority scale from the Style Guide.
  static Color priorityColor(int level) => switch (level) {
    5 => const Color(0xFFD42325), // P5 Critical
    4 => const Color(0xFFEC6F00), // P4 High
    3 => const Color(0xFFF0B135), // P3 Medium
    2 => const Color(0xFFACC455), // P2 Minor
    _ => const Color(0xFF49AF7E), // P1 Low
  };

  static Color priorityForeground(int level) => switch (level) {
    2 || 3 => saffronInk,
    _ => Colors.white,
  };

  static Color priorityBackground(int level) =>
      priorityColor(level).withValues(alpha: 0.14);
}

abstract final class AppFonts {
  static const body = 'KantumruyPro';
  static const display = 'Sora';

  static TextStyle displayStyle({
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.w700,
    Color color = AppColors.ink,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: display,
      fontFamilyFallback: const [body],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

ThemeData buildSrolanhCityTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.teal,
    primary: AppColors.teal,
    secondary: AppColors.saffron,
    surface: AppColors.paper,
    error: AppColors.danger,
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: AppFonts.body,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.paper,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.body,
        color: AppColors.ink,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.border, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.mutedSurface,
      selectedColor: AppColors.tealSoft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: const BorderSide(color: AppColors.border),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.teal, width: 1.6),
      ),
    ),
  );
}
