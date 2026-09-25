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

REM Find keytool. It ships with every JDK, and Android Studio bundles one, but
REM neither puts it on PATH on a normal Windows install - which is why running
REM this script used to stop here.
set "KEYTOOL="
for /f "delims=" %%K in ('where keytool 2^>nul') do if not defined KEYTOOL set "KEYTOOL=%%K"
if not defined KEYTOOL if defined JAVA_HOME if exist "%JAVA_HOME%\bin\keytool.exe" set "KEYTOOL=%JAVA_HOME%\bin\keytool.exe"
if not defined KEYTOOL for %%D in (
  "%ProgramFiles%\Android\Android Studio\jbr\bin"
  "%ProgramFiles%\Android\Android Studio\jre\bin"
  "%LOCALAPPDATA%\Programs\Android Studio\jbr\bin"
  "%LOCALAPPDATA%\Programs\Android Studio\jre\bin"
  "%ProgramFiles%\Android\Android Studio1\jbr\bin"
) do if not defined KEYTOOL if exist "%%~D\keytool.exe" set "KEYTOOL=%%~D\keytool.exe"
if not defined KEYTOOL for /d %%J in ("%ProgramFiles%\Java\*" "%ProgramFiles%\Eclipse Adoptium\*" "%ProgramFiles%\Microsoft\jdk*") do (
  if not defined KEYTOOL if exist "%%~J\bin\keytool.exe" set "KEYTOOL=%%~J\bin\keytool.exe"
)

if not defined KEYTOOL (
  echo keytool was not found.
  echo.
  echo It comes with Java. Either:
  echo   1^) Install Android Studio ^(it bundles one^), or
  echo   2^) Install Temurin JDK 17 from https://adoptium.net
  echo.
  echo If Android Studio is already installed somewhere else, find keytool.exe
  echo under its jbr\bin folder and run this script again from a terminal where
  echo that folder is on PATH.
  pause
  exit /b 1
)
echo Using keytool: %KEYTOOL%
echo.

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

"%KEYTOOL%" -genkeypair -v -keystore "android\app\upload-keystore.jks" -storetype PKCS12 ^
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
"%KEYTOOL%" -list -v -keystore "android\app\upload-keystore.jks" -alias upload -storepass %KSPASS% | findstr "SHA1 SHA256"
echo.
echo For the GitHub secret UDRIVE_KEYSTORE_BASE64, open Git Bash in this folder
echo and run:
echo   base64 -w0 android/app/upload-keystore.jks ^> keystore.b64.txt
echo Then open keystore.b64.txt, copy everything, and paste it into the secret.
echo Delete keystore.b64.txt afterwards.
echo.
pause
exit /b 0

:error
echo.
echo keytool failed. Nothing was created.
pause
exit /b 1
