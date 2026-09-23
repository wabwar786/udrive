#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/udrive_unified_mobile/lib"

if [[ ! -d "$ROOT" ]]; then
  echo "udrive_unified_mobile/lib was not found."
  echo "Extract/run this patch from the repository root."
  exit 1
fi

changed=0

while IFS= read -r -d '' file; do
  if grep -q 'FilePicker\.platform\.pickFiles(' "$file"; then
    python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
content = path.read_text(encoding="utf-8")
updated = content.replace(
    "FilePicker.platform.pickFiles(",
    "FilePicker.pickFiles("
)
path.write_text(updated, encoding="utf-8")
PY
    echo "Updated: $file"
    changed=$((changed + 1))
  fi
done < <(find "$ROOT" -type f -name '*.dart' -print0)

echo
echo "Completed. Dart files changed: $changed"

if [[ "$changed" -eq 0 ]]; then
  echo "No old FilePicker.platform.pickFiles calls were found."
fi
