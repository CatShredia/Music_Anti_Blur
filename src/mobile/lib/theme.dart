import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class VizeColors {
  static const bg = Color(0xFF050A08);
  static const bgElevated = Color(0xFF0B1310);
  static const surface = Color(0xFF13211C);
  static const stroke = Color(0xFF1A2E28);
  static const accent = Color(0xFF0CB880);
  static const accentMuted = Color(0xFF6CE4B4);
  static const accentDim = Color(0xFF3D7A68);
  static const text = Color(0xFFF4FBF7);
  static const textOnAccent = Color(0xFF05241C);
  static const danger = Color(0xFFE84040);
  static const dangerBg = Color(0xFF2A1212);
}

class VizeRadii {
  static const pill = 999.0;
  static const card = 18.0;
  static const field = 18.0;
}

class VizeTheme {
  static const overlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: VizeColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData data() {
    const scheme = ColorScheme.dark(
      primary: VizeColors.accent,
      onPrimary: VizeColors.textOnAccent,
      secondary: VizeColors.accentMuted,
      onSecondary: VizeColors.textOnAccent,
      surface: VizeColors.bg,
      onSurface: VizeColors.text,
      error: VizeColors.danger,
      onError: VizeColors.text,
      outline: VizeColors.stroke,
      surfaceContainerHighest: VizeColors.surface,
    );

    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(VizeRadii.card),
    );
    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(VizeRadii.pill),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: VizeColors.bg,
      canvasColor: VizeColors.bg,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: const AppBarTheme(
        systemOverlayStyle: overlay,
        backgroundColor: VizeColors.bg,
        foregroundColor: VizeColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: VizeColors.surface,
        contentTextStyle: const TextStyle(color: VizeColors.text, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: rounded,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: VizeColors.accent,
          foregroundColor: VizeColors.textOnAccent,
          disabledBackgroundColor: VizeColors.surface,
          disabledForegroundColor: VizeColors.accentDim,
          minimumSize: const Size.fromHeight(48),
          shape: pill,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: VizeColors.text,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: VizeColors.accentDim),
          shape: pill,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: VizeColors.accentMuted,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: VizeColors.bgElevated,
        hintStyle: const TextStyle(color: VizeColors.accentDim),
        labelStyle: const TextStyle(color: VizeColors.accentDim),
        floatingLabelStyle: const TextStyle(color: VizeColors.accentMuted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VizeRadii.field),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VizeRadii.field),
          borderSide: const BorderSide(color: VizeColors.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VizeRadii.field),
          borderSide: const BorderSide(color: VizeColors.accent),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(VizeRadii.field),
          borderSide: const BorderSide(color: VizeColors.danger),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: VizeColors.accent),
      dividerColor: VizeColors.stroke,
      iconTheme: const IconThemeData(color: VizeColors.accentMuted, size: 22),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: VizeColors.text,
          height: 1.15,
        ),
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: VizeColors.text,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: VizeColors.text,
        ),
        bodyMedium: TextStyle(fontSize: 16, color: VizeColors.text, height: 1.4),
        bodySmall: TextStyle(fontSize: 13, color: VizeColors.accentDim, height: 1.35),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.1,
          color: VizeColors.accent,
        ),
      ),
    );
  }
}
