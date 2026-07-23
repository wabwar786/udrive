#!/usr/bin/env bash
set -euo pipefail

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter is not installed or is not available in PATH." >&2
  exit 1
}

flutter create . --platforms=android,ios,web --project-name=udrive_mobile --org=com.udrive
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release --dart-define=DEFAULT_MODE=customer

echo "APK created: build/app/outputs/flutter-apk/app-release.apk"
