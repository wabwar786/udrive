#!/usr/bin/env bash
set -euo pipefail
API_URL="${1:-https://udrive-api-production.up.railway.app}"
ADMIN_URL="${2:-}"
MOBILE_URL="${3:-}"

check() {
  local url="$1"
  printf 'Checking %s ... ' "$url"
  curl --fail --silent --show-error --max-time 20 "$url" >/dev/null
  echo PASS
}

check "$API_URL/health/live"
check "$API_URL/health/ready"
if [[ -n "$ADMIN_URL" ]]; then check "$ADMIN_URL"; fi
if [[ -n "$MOBILE_URL" ]]; then check "$MOBILE_URL"; fi
