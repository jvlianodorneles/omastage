# Omarchy Stage Manager

An Omarchy Shell plugin that turns the left edge of the focused monitor into a compact Stage Manager holding every Hyprland window from the normal workspaces. The sidebar uses a layer-shell exclusive zone, so Hyprland reserves the space it needs and your windows are never covered.

![Omarchy Stage Manager](docs/screenshot.png)

## Features

- windows from every workspace on the focused monitor;
- a transparent stage that sits on the desktop instead of behind a settings-panel frame;
- a narrow sidebar that reserves space rather than overlapping your windows;
- floating thumbnails with soft corners, depth, hover animations and an overlaid app icon;
- compact per-application grouping with genuinely stacked cards;
- live previews through `hyprland-toplevel-export-v1`;
- minimal workspace selectors for applications with more than one window;
- click a preview or a selector to switch workspace and focus that window;
- an icon in the Omarchy top bar;
- keyboard navigation with the arrow keys, `Tab`, `Shift+Tab`, `Enter` and `Esc`;
- colors and sizing consistent with the Omarchy theme;
- built only from the QML components shipped with vanilla Omarchy, no extra effects modules.

Layer surfaces, special windows and special workspaces are never shown.

## Requirements

- Omarchy 4 or later;
- Quickshell 0.3.1 or later;
- Hyprland with `hyprland-toplevel-export-v1` support.

## Local installation via symlink

```bash
git clone https://github.com/debba/omarchy-stage-manager ~/Projects/omarchy-stage-manager
cd ~/Projects/omarchy-stage-manager
./install.sh
```

The script:

1. validates the manifest;
2. creates `~/.config/omarchy/plugins/debba.stage-manager` as a symlink to the repository;
3. enables the widget in the right section of the bar;
4. adds `SUPER+GRAVE` to `~/.config/hypr/bindings.lua` if it is free;
5. reloads and validates Hyprland;
6. restarts Omarchy Shell so both plugin entry points are mounted.

`SUPER+TAB` is left alone because Omarchy uses it to move to the next workspace.

Because the plugin is symlinked, a rescan may be needed after editing the source files:

```bash
omarchy-shell shell rescanPlugins
```

The overlay entry point is `keepLoaded`, so a rescan does not always pick up changes to `StageManager.qml`. When that happens, use `omarchy restart shell`.

## Usage

- left-click the Stage Manager icon in the bar;
- or press `SUPER+GRAVE`;
- click a preview to activate the window it shows, even when it lives on another workspace;
- for grouped applications, hover the small numbered badges to switch preview and click a badge to open that window;
- click outside the panel or press `Esc` to dismiss it.

## Uninstall

```bash
./uninstall.sh
```

The script removes only the symlink created by this repository and the marked binding block.

## License

MIT — see [LICENSE](LICENSE).
