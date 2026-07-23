import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/localization/app_strings.dart';
import 'core/state/app_controller.dart';
import 'core/theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/splash_screen.dart';

class UDriveApp extends StatefulWidget {
  const UDriveApp({super.key});
  @override
  State<UDriveApp> createState() => _UDriveAppState();
}

class _UDriveAppState extends State<UDriveApp> {
  final AppController _controller = AppController();

  @override
  void initState() {
    super.initState();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => AppControllerScope(
          controller: _controller,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'uDrive',
            theme: AppTheme.light,
            locale: _controller.locale,
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: !_controller.initialized
                ? const SplashScreen()
                : _controller.loggedIn
                    ? const MainShell()
                    : const LoginScreen(),
          ),
        ),
      );
}
