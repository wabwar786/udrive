@echo off
setlocal
where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter is not installed or is not available in PATH.
  echo Install Flutter and Android Studio, then run this file again.
  exit /b 1
)

call flutter create . --platforms=android,ios,web --project-name=udrive_mobile --org=com.udrive
if errorlevel 1 exit /b 1

call flutter pub get
if errorlevel 1 exit /b 1

call flutter analyze --no-fatal-infos --no-fatal-warnings
if errorlevel 1 exit /b 1

call flutter test
if errorlevel 1 exit /b 1

call flutter build apk --release --dart-define=DEFAULT_MODE=customer
if errorlevel 1 exit /b 1

echo.
echo APK created successfully:
echo build\app\outputs\flutter-apk\app-release.apk
endlocal
