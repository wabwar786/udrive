# Railway deployment

1. Commit the `udrive_unified_mobile` folder to GitHub.
2. In Railway, create a new service from the repository.
3. Set the service root directory to `/udrive_unified_mobile` when it is inside a monorepo.
4. Railway will detect the included Dockerfile.
5. Do not set a custom build command.
6. Do not set a custom start command.
7. Do not manually create a `PORT` variable.
8. Generate a public domain after deployment.

The Railway deployment is a Flutter web preview. Android and iOS releases must be built using Flutter tooling and distributed through testing/app-store channels.
