# Deploy UDrive Phase 1 with GitHub and Railway

This repository is a monorepo with three independent web services:

| Railway service | Root directory | Result |
|---|---|---|
| UDrive Admin | `/admin_portal` | Next.js Super Admin portal |
| UDrive Customer | `/customer_app` | Flutter customer web preview |
| UDrive Driver | `/driver_app` | Flutter driver web preview |

The Flutter services use Dockerfiles to generate missing web scaffolding, build release web bundles, and serve them on Railway's assigned `PORT`.

## 1. Upload the project to GitHub

Create an empty GitHub repository named `udrive` without adding a README or `.gitignore` on GitHub.

Open Git Bash or a terminal in this extracted project folder and run:

```bash
git init
git add .
git commit -m "Initial UDrive Phase 1 frontend"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/udrive.git
git push -u origin main
```

Replace `YOUR_USERNAME` with your GitHub username.

## 2. Deploy the Next.js admin portal

1. In Railway, select **New Project** → **Deploy from GitHub repo**.
2. Select the `udrive` repository.
3. Open the created service → **Settings**.
4. Set **Root Directory** to `/admin_portal`.
5. Rename the service to `udrive-admin`.
6. Railway will detect `admin_portal/Dockerfile` and deploy it.
7. Open **Settings** → **Networking** → **Generate Domain**.

No environment variables are required for Phase 1.

## 3. Deploy the customer web preview

1. Inside the same Railway project, click **New** → **GitHub Repo**.
2. Select the same `udrive` repository.
3. Set **Root Directory** to `/customer_app`.
4. Rename the service to `udrive-customer`.
5. Deploy and generate a public domain under **Networking**.

## 4. Deploy the driver web preview

1. Add the same GitHub repository as another service.
2. Set **Root Directory** to `/driver_app`.
3. Rename it to `udrive-driver`.
4. Deploy and generate a public domain.

## 5. Future updates

After editing the code:

```bash
git add .
git commit -m "Update UDrive UI"
git push
```

Railway automatically redeploys services connected to the updated branch.

## Important mobile-app limitation

Railway hosts browser-accessible previews. Android and iOS releases are separate build artifacts:

```bash
cd customer_app
flutter create . --platforms=android,ios,web
flutter build apk --release
```

Repeat inside `driver_app`. Publishing to Google Play or Apple App Store requires their respective developer accounts and signing setup.

## Troubleshooting

### Railway deploys the repository root instead of the app
Confirm the service **Root Directory** exactly matches one of:

- `/admin_portal`
- `/customer_app`
- `/driver_app`

### Application failed to respond
Do not manually set a fixed `PORT`. Railway injects `PORT`; the included Dockerfiles listen on it and bind to `0.0.0.0`.

### Flutter build is slow
The first Docker build downloads the Flutter image and compiles the web release. Later builds may use cached layers. Check Railway deployment logs for the exact failed command.

## Admin npm build error correction

If an earlier deployment failed with `npm error Exit handler never called!`,
use the corrected files included in this archive. The Admin Dockerfile now uses
Node 20 on Debian instead of Node 22 on Alpine, and the lockfile no longer
contains private registry addresses. Push the correction and deploy the latest
GitHub commit.
