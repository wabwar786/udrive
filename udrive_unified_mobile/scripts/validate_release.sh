#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

printf '\n[1/3] API release build\n'
cd "$ROOT/udrive_api"
dotnet restore UDrive.Api.csproj
dotnet publish UDrive.Api.csproj -c Release -o ./publish --no-restore /p:UseAppHost=false

printf '\n[2/3] Admin production build\n'
cd "$ROOT/admin_portal"
npm ci --no-audit --no-fund
npm run build

printf '\n[3/3] Flutter analysis and web build\n'
cd "$ROOT/udrive_unified_mobile"
flutter pub get
flutter analyze
flutter test
flutter build web --release --no-wasm-dry-run

printf '\nAll release validation commands passed.\n'
