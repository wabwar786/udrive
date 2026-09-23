# Validation

Static project checks cover:

- Dart delimiter balance
- Relative import targets
- English/Urdu localization-key parity
- Referenced image assets
- Empty visible-action callbacks
- Required Android, iOS, web and Docker files
- YAML/XML/JSON syntax
- Shell-script syntax

GitHub Actions additionally performs:

- Missing native-scaffolding completion
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- Flutter web release build
- Android APK build
- Android AAB build
