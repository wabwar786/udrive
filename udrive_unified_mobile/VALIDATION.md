# Validation report

The packaged repository update was checked for:

- Balanced Dart delimiters across 25 Dart files
- Valid relative imports
- English and Urdu coverage for all 234 localization keys used by screens
- No empty visible button/tap callbacks
- Referenced local image assets
- Required Android, iOS and web platform files
- JSON validity for web and iOS asset manifests
- XML validity for Android resources and manifests
- YAML validity for the monorepo GitHub Actions workflow
- Shell syntax for the local APK build script
- Railway Dockerfile and Nginx configuration presence
- APK and AAB artifact paths in GitHub Actions

## Compiler note

The generation environment does not contain the Flutter SDK, so Flutter/Gradle compilation could not be executed locally. After the update is pushed, the included GitHub Actions workflow runs project validation, `flutter analyze`, tests, APK compilation and AAB compilation. Railway separately compiles the Flutter web release through the included Dockerfile.
