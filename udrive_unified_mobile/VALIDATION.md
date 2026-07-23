# Validation

The repository patch was checked for:

- Balanced Dart parentheses, brackets and braces
- Existing relative Dart imports
- English/Urdu localization-key parity
- Missing localization keys used by screens
- Empty `onPressed`, `onTap` and `onChanged` callbacks
- GitHub Actions YAML syntax
- JSON validity for web/iOS metadata
- Android/iOS XML and plist parseability where applicable
- Shell script syntax
- Required Android, web, asset and source folders

The project includes a GitHub Actions workflow that performs the authoritative Flutter checks after upload:

```text
flutter create
flutter pub get
flutter analyze
flutter test
flutter build apk
flutter build appbundle
```
