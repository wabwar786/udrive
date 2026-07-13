import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/localization/app_language.dart';
import 'core/state/app_controller.dart';
import 'core/theme/app_theme.dart';
import 'screens/app_mode_shell.dart';

class UDriveMobileApp extends StatefulWidget {
  const UDriveMobileApp({super.key});

  @override
  State<UDriveMobileApp> createState() => _UDriveMobileAppState();
}

class _UDriveMobileAppState extends State<UDriveMobileApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    const defaultMode = String.fromEnvironment(
      'DEFAULT_MODE',
      defaultValue: 'customer',
    );
    _controller = AppController(
      initialMode: defaultMode == 'driver' ? UserMode.driver : UserMode.customer,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'UDrive',
          locale: _controller.locale,
          supportedLocales: const [Locale('en'), Locale('ur')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light,
          builder: (context, child) {
            return AppControllerScope(
              controller: _controller,
              child: AppLanguageScope(
                locale: _controller.locale,
                setLanguage: _controller.setLanguage,
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const AppModeShell(),
        );
      },
    );
  }
}
