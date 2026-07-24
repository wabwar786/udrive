#!/usr/bin/env bash
set -euo pipefail
flutter pub get
python3 tool/validate_project.py
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
flutter build apk --release --dart-define=DEFAULT_MODE=customer
printf '\nAPK created at: build/app/outputs/flutter-apk/app-release.apk\n'
