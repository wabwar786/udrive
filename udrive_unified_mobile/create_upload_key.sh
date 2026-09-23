#!/usr/bin/env bash
# Creates the Google Play upload key for UDrive (run ONCE, on your own machine).
# Output: android/app/upload-keystore.jks and android/key.properties
# Keep both files and the password safe forever. Never commit them to Git.
set -euo pipefail
cd "$(dirname "$0")"
if [ -f android/app/upload-keystore.jks ]; then
  echo "android/app/upload-keystore.jks already exists. Not overwriting."; exit 1
fi
read -r -s -p "Choose a strong password (min 8 chars, letters and numbers only): " KSPASS; echo
keytool -genkeypair -v -keystore android/app/upload-keystore.jks -storetype PKCS12 \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload \
  -storepass "$KSPASS" -keypass "$KSPASS" \
  -dname "CN=UDrive, O=Tech Geni Ltd., L=Muzaffarabad, C=PK"
cat > android/key.properties <<PROPS
storePassword=$KSPASS
keyPassword=$KSPASS
keyAlias=upload
storeFile=upload-keystore.jks
PROPS
chmod 600 android/key.properties
echo "Done. Back up android/app/upload-keystore.jks and android/key.properties now."
keytool -list -v -keystore android/app/upload-keystore.jks -alias upload -storepass "$KSPASS" | grep -E "SHA1|SHA256"
echo "For GitHub Actions secret UDRIVE_KEYSTORE_BASE64:  base64 -w0 android/app/upload-keystore.jks"
