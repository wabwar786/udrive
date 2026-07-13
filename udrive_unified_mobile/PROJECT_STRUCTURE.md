# Project structure

```text
lib/
├── app.dart
├── main.dart
├── core/
│   ├── localization/app_language.dart
│   ├── state/app_controller.dart
│   ├── theme/app_theme.dart
│   └── widgets/
│       ├── mode_switch_card.dart
│       └── udrive_logo.dart
├── data/
│   ├── driver_dummy_data.dart
│   └── dummy_data.dart
├── models/
│   ├── driver_models.dart
│   └── models.dart
└── screens/
    ├── app_mode_shell.dart
    ├── customer_shell.dart
    ├── home/
    ├── explore/
    ├── ride/
    ├── packages/
    ├── trips/
    ├── profile/
    └── driver/
```

`AppController` owns the active mode, locale, driver approval state and online state. The frontend is intentionally dependency-light and ready to connect to real repositories later.
