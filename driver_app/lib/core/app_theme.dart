import 'package:flutter/material.dart';
class AppColors { static const primary = Color(0xFF0F766E); static const secondary = Color(0xFF2563EB); static const accent = Color(0xFFF59E0B); static const background = Color(0xFFF6F8FB); static const text = Color(0xFF0F172A); static const muted = Color(0xFF64748B); }
class AppTheme { static ThemeData get light => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, primary: AppColors.primary, secondary: AppColors.secondary),
  scaffoldBackgroundColor: AppColors.background,
  appBarTheme: const AppBarTheme(backgroundColor: AppColors.background, elevation: 0),
  cardTheme: CardThemeData(color: Colors.white, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: const BorderSide(color: Color(0xFFE7ECF3)))),
  inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFDCE3EC)))),
  filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontWeight: FontWeight.w800))),
); }
