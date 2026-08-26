#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="debba.stage-manager"
PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
BINDINGS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua"

if omarchy plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled)' >/dev/null; then
  omarchy plugin disable "$PLUGIN_ID"
fi

if [[ -f "$BINDINGS_FILE" ]] && grep -Fq -- "-- >>> $PLUGIN_ID >>>" "$BINDINGS_FILE"; then
  cp -- "$BINDINGS_FILE" "$BINDINGS_FILE.bak.$(date +%s)"
  python - "$BINDINGS_FILE" "$PLUGIN_ID" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
plugin_id = sys.argv[2]
start = f"-- >>> {plugin_id} >>>"
end = f"-- <<< {plugin_id} <<<"
lines = path.read_text().splitlines(keepends=True)
out = []
skipping = False
for line in lines:
    if line.rstrip("\n") == start:
        skipping = True
        if out and out[-1].strip() == "":
            out.pop()
        continue
    if skipping and line.rstrip("\n") == end:
        skipping = False
        continue
    if not skipping:
        out.append(line)
path.write_text("".join(out))
PY
  hyprctl reload
  errors=$(hyprctl configerrors)
  if [[ -n "$errors" ]]; then
    printf '%s\n' "$errors" >&2
    exit 1
  fi
fi

if [[ -L "$INSTALL_DIR" && "$(readlink -f -- "$INSTALL_DIR")" == "$PLUGIN_DIR" ]]; then
  rm -- "$INSTALL_DIR"
elif [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
  echo "uninstall.sh: not removing unrelated path $INSTALL_DIR" >&2
fi

omarchy-shell shell rescanPlugins
omarchy restart shell
for _ in {1..50}; do
  if omarchy-shell shell ping >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
printf 'Uninstalled %s\n' "$PLUGIN_ID"
