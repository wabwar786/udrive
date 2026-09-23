# Flutter Railway compilation fix

This update fixes the Flutter Web compilation error reported by Railway:

```text
lib/screens/explore/explore_screen.dart:19:24:
Error: Can't find ')' to match '('.
```

## Corrected files

- `customer_app/lib/screens/explore/explore_screen.dart`
- `driver_app/lib/screens/home_screen.dart`
- `customer_app/Dockerfile`
- `driver_app/Dockerfile`

The customer package card was rewritten as a structured reusable widget. A second unmatched-delimiter problem discovered in the Driver home screen was corrected before deployment.

The Flutter runtime images now use `node:20-bookworm-slim` instead of `node:22-alpine` for more reliable npm/serve installation.

## Deploy

Copy the corrected files into the same paths in your GitHub repository, then run:

```bash
git add customer_app driver_app
git commit -m "Fix Flutter Railway web builds"
git push
```

Railway should automatically build the newest commit. If it does not, use **Deploy Latest Commit** for the Customer and Driver services.

Keep these Railway root directories:

- Customer service: `/customer_app`
- Driver service: `/driver_app`

No environment variables are required for this dummy-data version. Do not manually create `PORT`; Railway provides it automatically.
