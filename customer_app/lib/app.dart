import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/localization/app_language.dart';
import 'core/theme/app_theme.dart';
import 'screens/customer_shell.dart';

class UDriveCustomerApp extends StatefulWidget {
  const UDriveCustomerApp({super.key});

  @override
  State<UDriveCustomerApp> createState() => _UDriveCustomerAppState();
}

class _UDriveCustomerAppState extends State<UDriveCustomerApp> {
  Locale _locale = const Locale('en');

  void _setLanguage(String code) {
    setState(() => _locale = Locale(code));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UDrive',
      locale: _locale,
      supportedLocales: const [Locale('en'), Locale('ur')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light,
      builder: (context, child) => AppLanguageScope(
        locale: _locale,
        setLanguage: _setLanguage,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const CustomerShell(),
    );
  }
}
