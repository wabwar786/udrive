#!/usr/bin/env bash
set -euo pipefail
for app in customer_app driver_app; do
  echo "Preparing $app..."
  (cd "$app" && flutter create . --platforms=android,ios,web && flutter pub get)
done
echo "Flutter project scaffolding is ready."
