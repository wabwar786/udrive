#!/usr/bin/env bash
set -euo pipefail
if [ ! -f android/gradle/wrapper/gradle-wrapper.jar ]; then
  flutter create . --platforms=android,ios,web --project-name=udrive_mobile --org=com.udrive
fi
flutter pub get
python3 tool/validate_project.py
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release --dart-define=DEFAULT_MODE=customer --dart-define=API_BASE_URL=https://udrive-api-production.up.railway.app
printf '\nAPK created at: build/app/outputs/flutter-apk/app-release.apk\n'
