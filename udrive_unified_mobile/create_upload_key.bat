@echo off
REM Creates the Google Play upload key for UDrive (run ONCE, on your own PC).
REM Output: android\app\upload-keystore.jks and android\key.properties
REM Keep both files and the password safe forever - without them you cannot
REM publish updates. Never commit them to Git.
setlocal
if exist android\app\upload-keystore.jks (
  echo android\app\upload-keystore.jks already exists. Not overwriting.
  exit /b 1
)
set /p KSPASS=Choose a strong password (min 8 chars, letters and numbers only): 
keytool -genkeypair -v -keystore android\app\upload-keystore.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload -storepass %KSPASS% -keypass %KSPASS% -dname "CN=UDrive, O=Tech Geni Ltd., L=Muzaffarabad, C=PK" || goto :error
(
  echo storePassword=%KSPASS%
  echo keyPassword=%KSPASS%
  echo keyAlias=upload
  echo storeFile=upload-keystore.jks
) > android\key.properties
echo.
echo Done. Back up android\app\upload-keystore.jks and android\key.properties now.
keytool -list -v -keystore android\app\upload-keystore.jks -alias upload -storepass %KSPASS% | findstr "SHA1 SHA256"
exit /b 0
:error
echo keytool failed. Install JDK 17 (comes with Android Studio) and make sure keytool is on PATH.
exit /b 1
