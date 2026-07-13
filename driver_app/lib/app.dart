import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/app_language.dart';
import 'core/app_theme.dart';
import 'screens/driver_shell.dart';

class UDriveDriverApp extends StatefulWidget {
  const UDriveDriverApp({super.key});
  @override State<UDriveDriverApp> createState() => _UDriveDriverAppState();
}
class _UDriveDriverAppState extends State<UDriveDriverApp> {
  Locale locale = const Locale('en');
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    supportedLocales: const [Locale('en'), Locale('ur')],
    localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    theme: AppTheme.light,
    builder: (context, child) => DriverLanguageScope(locale: locale, setLanguage: (code) => setState(() => locale = Locale(code)), child: child ?? const SizedBox()),
    home: const DriverShell(),
  );
}
