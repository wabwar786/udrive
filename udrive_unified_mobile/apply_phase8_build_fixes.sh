#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_ROOT="$ROOT/udrive_unified_mobile/lib"
CSS_FILE="$ROOT/admin_portal/app/verification/verification.module.css"

if [[ ! -d "$MOBILE_ROOT" ]]; then
  echo "Missing folder: udrive_unified_mobile/lib"
  echo "Extract this ZIP into the repository root."
  exit 1
fi

if [[ ! -f "$CSS_FILE" ]]; then
  echo "Missing file: admin_portal/app/verification/verification.module.css"
  echo "Extract this ZIP into the repository root."
  exit 1
fi

dart_changed=0

while IFS= read -r -d '' file; do
  if grep -Fq 'FilePicker.platform.pickFiles(' "$file"; then
    python3 - "$file" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace(
    "FilePicker.platform.pickFiles(",
    "FilePicker.pickFiles("
)
path.write_text(text, encoding="utf-8")
PY
    echo "Flutter fixed: $file"
    dart_changed=$((dart_changed + 1))
  fi
done < <(find "$MOBILE_ROOT" -type f -name '*.dart' -print0)

python3 - "$CSS_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
updated = text.replace(
    "}button{font:inherit}",
    "}.page button,.loginPage button{font:inherit}"
)
if updated == text:
    updated = text.replace(
        "button{font:inherit}",
        ".page button,.loginPage button{font:inherit}"
    )
path.write_text(updated, encoding="utf-8")
PY

echo "Admin CSS fixed: $CSS_FILE"

if grep -RFn 'FilePicker.platform.pickFiles(' "$MOBILE_ROOT"; then
  echo "Old FilePicker calls still remain."
  exit 1
fi

if grep -Eq '(^|})button\{font:inherit\}' "$CSS_FILE"; then
  echo "Impure global button selector still remains."
  exit 1
fi

echo
echo "Flutter files changed: $dart_changed"
echo "Validation passed. Both Railway build errors are fixed."
