# Railway Web Preview

This project can be deployed as a Flutter web preview from the existing UDrive monorepo.

1. Push the complete update to GitHub.
2. Open the UDrive Mobile service in Railway.
3. Set **Root Directory** to:

```text
/udrive_unified_mobile
```

4. Keep the included `Dockerfile`.
5. Remove any custom build command.
6. Remove any custom start command.
7. Do not manually create a `PORT` variable.
8. Deploy the latest GitHub commit and generate a domain under Networking.

Railway hosts the web build only. Use GitHub Actions or local Flutter tooling for APK/AAB files.
