@echo off
REM Builds the signed .aab for Google Play. Needs android\key.properties
REM (run create_upload_key.bat once first) and your Android Maps key.
setlocal
if not exist android\key.properties (
  echo android\key.properties missing. Run create_upload_key.bat first.
  exit /b 1
)
set /p MAPSKEY=Android Google Maps API key: 
flutter pub get || goto :error
flutter build appbundle --release --dart-define=DEFAULT_MODE=customer --dart-define=API_BASE_URL=https://udrive-api-production.up.railway.app -Pmaps_key=%MAPSKEY% || goto :error
echo.
echo Upload this file to Play Console:
echo build\app\outputs\bundle\release\app-release.aab
exit /b 0
:error
echo Build failed. Review the error above.
exit /b 1
