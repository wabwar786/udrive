#!/usr/bin/env bash
# Creates the Google Play upload key for UDrive (run ONCE, on your own machine).
# Output: android/app/upload-keystore.jks and android/key.properties
# Keep both files and the password safe forever. Never commit them to Git.
set -euo pipefail
cd "$(dirname "$0")"
echo "Working in: $PWD"

# keytool ships with every JDK but is often not on PATH. Look where it lives.
KEYTOOL="$(command -v keytool || true)"
if [ -z "$KEYTOOL" ]; then
  for candidate in \
    "${JAVA_HOME:-}/bin/keytool" \
    "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" \
    "/Applications/Android Studio.app/Contents/jre/Contents/Home/bin/keytool" \
    "$HOME/Library/Java/JavaVirtualMachines"/*/Contents/Home/bin/keytool \
    /usr/lib/jvm/*/bin/keytool \
    "$HOME/.jdks"/*/bin/keytool
  do
    if [ -x "$candidate" ]; then KEYTOOL="$candidate"; break; fi
  done
fi
if [ -z "$KEYTOOL" ]; then
  echo "keytool was not found. Install Android Studio (it bundles a JDK) or Temurin JDK 17"
  echo "from https://adoptium.net, then run this script again."
  exit 1
fi
echo "Using keytool: $KEYTOOL"

if [ -f android/app/upload-keystore.jks ]; then
  echo "$PWD/android/app/upload-keystore.jks already exists. Not overwriting."; exit 1
fi
read -r -s -p "Choose a strong password (min 8 chars, letters and numbers only): " KSPASS; echo
"$KEYTOOL" -genkeypair -v -keystore android/app/upload-keystore.jks -storetype PKCS12 \
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
echo "Done. Back up these two files and the password now:"
echo "  $PWD/android/app/upload-keystore.jks"
echo "  $PWD/android/key.properties"
"$KEYTOOL" -list -v -keystore android/app/upload-keystore.jks -alias upload -storepass "$KSPASS" | grep -E "SHA1|SHA256"
echo "For GitHub Actions secret UDRIVE_KEYSTORE_BASE64:  base64 -w0 android/app/upload-keystore.jks"
