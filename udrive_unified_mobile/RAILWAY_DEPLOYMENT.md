# Railway Web Deployment

Use the existing GitHub repository and Mobile Railway service.

## Service settings

```text
Repository: wabwar786/udrive
Branch: main
Root directory: /udrive_unified_mobile
```

Do not configure:

- Custom build command
- Custom start command
- Manual PORT variable

Deploy the latest commit. The Dockerfile uses a cached Flutter dependency layer, builds the release web application and serves it through Nginx.

After deployment, hard-refresh the browser if an older Flutter web version is cached.
