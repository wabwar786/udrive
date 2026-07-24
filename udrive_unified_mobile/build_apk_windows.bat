@echo off
setlocal
if not exist android\gradle\wrapper\gradle-wrapper.jar (
  flutter create . --platforms=android,ios,web --project-name=udrive_mobile --org=com.udrive || goto :error
)
flutter pub get || goto :error
python tool\validate_project.py || goto :error
flutter analyze --no-fatal-infos --no-fatal-warnings || goto :error
flutter test || goto :error
flutter build apk --release --dart-define=DEFAULT_MODE=customer --dart-define=API_BASE_URL=https://udrive-api-production.up.railway.app || goto :error
echo.
echo APK created at: build\app\outputs\flutter-apk\app-release.apk
exit /b 0
:error
echo.
echo Build failed. Review the error shown above.
exit /b 1
