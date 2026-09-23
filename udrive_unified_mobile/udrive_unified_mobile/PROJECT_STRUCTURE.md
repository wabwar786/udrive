# Project Structure

```text
lib/
├── core/
│   ├── localization/
│   ├── services/
│   │   ├── map_config.dart
│   │   └── simulated_location_service.dart
│   ├── state/app_controller.dart
│   ├── theme/
│   └── widgets/
├── data/
│   ├── dummy_data.dart
│   └── models.dart
└── screens/
    ├── auth/
    ├── common/
    ├── customer/
    ├── driver/
    ├── maps/live_tracking_screen.dart
    ├── safety/safety_hub_screen.dart
    ├── main_shell.dart
    └── splash_screen.dart
```

`AppController` is the dummy state boundary. Later, replace its local mutations with authenticated API repositories while keeping screen contracts stable.
