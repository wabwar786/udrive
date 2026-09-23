@echo off
REM Creates the Google Play upload key for UDrive (run ONCE, on your own PC).
REM
REM Output (full paths are printed at the end):
REM   <this folder>\android\app\upload-keystore.jks
REM   <this folder>\android\key.properties
REM
REM Keep both files and the password safe forever - without them you cannot
REM publish updates. Never commit them to Git.
setlocal

REM Work in this script's own folder, whatever folder the window started in.
REM "Run as administrator" starts in C:\Windows\System32, which is where the
REM keystore used to land when the paths were relative to the current folder.
cd /d "%~dp0"
echo Working in: %CD%
echo.

where keytool >nul 2>&1
if errorlevel 1 (
  echo keytool was not found on PATH.
  echo Install JDK 17 ^(Android Studio includes it^) and open a NEW terminal, or run
  echo this script from the Android Studio Terminal, then try again.
  pause
  exit /b 1
)

if not exist "android\app" (
  echo Could not find the android\app folder next to this script.
  echo Run this file from inside the udrive_unified_mobile folder.
  pause
  exit /b 1
)

if exist "android\app\upload-keystore.jks" (
  echo A keystore already exists at:
  echo   %CD%\android\app\upload-keystore.jks
  echo Not overwriting it. Delete it first only if you are certain the app has
  echo never been uploaded to Google Play with it.
  pause
  exit /b 1
)

set /p KSPASS=Choose a strong password (min 8 chars, letters and numbers only): 

keytool -genkeypair -v -keystore "android\app\upload-keystore.jks" -storetype PKCS12 ^
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload ^
  -storepass %KSPASS% -keypass %KSPASS% ^
  -dname "CN=UDrive, O=Tech Geni Ltd., L=Muzaffarabad, C=PK" || goto :error

(
  echo storePassword=%KSPASS%
  echo keyPassword=%KSPASS%
  echo keyAlias=upload
  echo storeFile=upload-keystore.jks
) > "android\key.properties"

echo.
echo ============================================================
echo Created:
echo   %CD%\android\app\upload-keystore.jks
echo   %CD%\android\key.properties
echo Back both files up now, along with the password.
echo ============================================================
echo.
keytool -list -v -keystore "android\app\upload-keystore.jks" -alias upload -storepass %KSPASS% | findstr "SHA1 SHA256"
echo.
echo For the GitHub secret UDRIVE_KEYSTORE_BASE64, run this in PowerShell from
echo this folder:
echo   [Convert]::ToBase64String([IO.File]::ReadAllBytes("android\app\upload-keystore.jks")) ^| Set-Clipboard
echo.
pause
exit /b 0

:error
echo.
echo keytool failed. Nothing was created.
pause
exit /b 1
