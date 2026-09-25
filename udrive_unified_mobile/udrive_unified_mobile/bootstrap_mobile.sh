#!/usr/bin/env bash
set -euo pipefail
flutter create . --platforms=android,ios,web --project-name=udrive_mobile --org=com.udrive
flutter pub get
printf '\nUDrive mobile scaffolding created. Run: flutter run\n'
