# Driver Home API Scope Hotfix

Replace `udrive_unified_mobile/lib/screens/driver/driver_home_screen.dart`.

Fixes Flutter build error caused by calling nonexistent `AppController.of(context)`.
The project exposes the controller through `AppControllerScope.of(context)`.
