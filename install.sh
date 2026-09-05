#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="dorneles.omastage"
PLUGIN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
INSTALL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
BINDINGS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua"
START_MARKER="-- >>> $PLUGIN_ID >>>"
END_MARKER="-- <<< $PLUGIN_ID <<<"

omarchy plugin validate "$PLUGIN_DIR"
mkdir -p -- "$(dirname -- "$INSTALL_DIR")"

if [[ -e "$INSTALL_DIR" || -L "$INSTALL_DIR" ]]; then
  if [[ ! -L "$INSTALL_DIR" || "$(readlink -f -- "$INSTALL_DIR")" != "$PLUGIN_DIR" ]]; then
    echo "install.sh: $INSTALL_DIR exists and is not this repository's symlink" >&2
    exit 1
  fi
else
  ln -s -- "$PLUGIN_DIR" "$INSTALL_DIR"
fi

omarchy-shell shell rescanPlugins
for _ in {1..50}; do
  if omarchy plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)' >/dev/null; then
    break
  fi
  sleep 0.1
done

if ! omarchy plugin list --json 2>/dev/null | jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id)' >/dev/null; then
  echo "install.sh: Omarchy did not discover $PLUGIN_ID" >&2
  exit 1
fi

omarchy plugin enable "$PLUGIN_ID" --section right

mkdir -p -- "$(dirname -- "$BINDINGS_FILE")"
touch "$BINDINGS_FILE"
if ! grep -Fq -- "$START_MARKER" "$BINDINGS_FILE"; then
  # Remove any legacy binding if present
  if grep -Fq -- "-- >>> debba.stage-manager >>>" "$BINDINGS_FILE"; then
    python3 - "$BINDINGS_FILE" "debba.stage-manager" <<'PY'
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
  fi

  cp -- "$BINDINGS_FILE" "$BINDINGS_FILE.bak.$(date +%s)"
  cat >>"$BINDINGS_FILE" <<'LUA'

-- >>> dorneles.omastage >>>
o.bind("CTRL + TAB", "OmaStage", "omarchy-shell shell toggle dorneles.omastage '{}'")
hl.layer_rule({ match = { namespace = "omastage" }, blur = true })
-- <<< dorneles.omastage <<<
LUA
  hyprctl reload
  if errors=$(hyprctl configerrors) && [[ -n "$errors" ]]; then
    printf '%s\n' "$errors" >&2
    exit 1
  fi
fi

# A fresh shell guarantees that both entry points of this multi-kind plugin
# (bar widget + keep-loaded overlay) are mounted after first installation.
omarchy restart shell
for _ in {1..50}; do
  if omarchy-shell shell ping >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
omarchy-shell shell ping >/dev/null

printf 'Installed %s\n  source: %s\n  link:   %s\n  toggle: CTRL+TAB\n' \
  "$PLUGIN_ID" "$PLUGIN_DIR" "$INSTALL_DIR"
