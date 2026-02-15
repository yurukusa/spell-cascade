#!/bin/bash
# Blocks commits that modify "sprawl-prone" files unless explicitly allowed.
# Rationale: keep the loop stable; prevent accidental changes to engine/project config.

set -euo pipefail

MSG_FILE="${1:-}"
if [[ -z "$MSG_FILE" || ! -f "$MSG_FILE" ]]; then
  echo "ERR_CODE:SPRAWL_HOOK missing commit message file" >&2
  exit 2
fi

# Files that frequently cause hard-to-debug regressions when touched casually.
BLOCKED_PATHS=(
  "project.godot"
  "scripts/background.gd"
)

# Detect if the commit touches any blocked paths.
changed=0
for p in "${BLOCKED_PATHS[@]}"; do
  if git diff --cached --name-only | grep -Fxq "$p"; then
    changed=1
  fi
done

if (( changed == 0 )); then
  exit 0
fi

if grep -q "\[SPRAWL_OK\]" "$MSG_FILE"; then
  exit 0
fi

echo "ERR_CODE:SPRAWL_BLOCK Commit touches sprawl-prone files (project config/background)." >&2
echo "Add [SPRAWL_OK] to the commit message if this change is intentional." >&2
echo "Touched files:" >&2
git diff --cached --name-only | grep -E '^(project\.godot|scripts/background\.gd)$' >&2 || true
exit 1
