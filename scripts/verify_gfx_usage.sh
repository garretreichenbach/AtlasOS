#!/usr/bin/env bash
set -euo pipefail
# Fail if any direct gfx.* usage is found outside Lib/atlasgfx.lua
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Search for gfx.<identifier> in lua files, excluding dist and the adapter file
out=$(rg --hidden --no-ignore -n "\bgfx\.[A-Za-z_]+\s*\(" "$ROOT" -g '!dist/**' -g '!**/*.md' -g '!**/*.txt' -g '!**/*.py' -g '!**/*.sh' --glob '**/*.lua' || true)
# Exclude any matches from generated dist/ directory to avoid false positives
out=$(echo "$out" | rg -v '/dist/' || true)
if [ -z "$out" ]; then
  echo "No direct gfx function invocations found."
  exit 0
fi
# Filter out allowed file (the adapter is allowed to call gfx.* directly)
filtered=$(echo "$out" | rg -v "^$ROOT/Lib/atlasgfx.lua:")
if [ -n "$filtered" ]; then
  echo "ERROR: direct gfx.* function calls found outside Lib/atlasgfx.lua:" >&2
  echo "$filtered" >&2
  exit 2
fi
echo "Only Lib/atlasgfx.lua contains direct gfx.* calls (function invocations) — OK."
exit 0

