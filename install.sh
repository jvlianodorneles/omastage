#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ID="debba.stage-manager"
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
  if omarchy menu keybindings --print 2>/dev/null | awk -F '→' '
    {
      key = $1
      sub(/[[:space:]]+$/, "", key)
      if (key == "SUPER + GRAVE") found = 1
    }
    END { exit found ? 0 : 1 }
  '; then
    echo "install.sh: SUPER+GRAVE is already assigned; shortcut was not installed" >&2
  else
    cp -- "$BINDINGS_FILE" "$BINDINGS_FILE.bak.$(date +%s)"
    cat >>"$BINDINGS_FILE" <<'LUA'

-- >>> debba.stage-manager >>>
-- SUPER+TAB remains Omarchy's "Next workspace" shortcut.
o.bind("SUPER + GRAVE", "Stage Manager", "omarchy-shell shell toggle debba.stage-manager '{}'")
-- <<< debba.stage-manager <<<
LUA
    hyprctl reload
    if errors=$(hyprctl configerrors) && [[ -n "$errors" ]]; then
      printf '%s\n' "$errors" >&2
      exit 1
    fi
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

printf 'Installed %s\n  source: %s\n  link:   %s\n  toggle: SUPER+GRAVE\n' \
  "$PLUGIN_ID" "$PLUGIN_DIR" "$INSTALL_DIR"
