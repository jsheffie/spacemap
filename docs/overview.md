# spacemap

spacemap is a lightweight native macOS menu bar utility that provides a visual overlay for users who manage their macOS workspaces using the yabai tiling window manager + skhd hotkey daemon in a 2D grid layout (e.g. 8×2 or 4×4 desktops).

In short: **it's a spatial HUD for yabai grid users** — think of it as a live minimap for your virtual desktops.

## What it solves

People who use [yabai](https://github.com/koekeishiya/yabai) + [skhd](https://github.com/asmvik/skhd) often arrange their desktops in a 2D grid (e.g. 8 columns × 2 rows, or 4×4) and use custom hotkeys to move around it. The problem is there's no visual reference — you have to keep the entire grid layout in your head.

spacemap provides that missing visual reference on demand.

## Core features

- Press **Ctrl+Space** (or a configurable hotkey) → a floating HUD overlay appears in the center of the screen.
- It renders your entire grid of desktops as cells.
- Each cell shows the windows currently on that desktop:
  - As colored rectangles (one color per app, scaled to real window positions), or
  - As app icons, or
  - A hybrid of both.
- The active desktop is highlighted.
- The view updates **live** as you switch spaces (it listens to yabai's `space_changed` signal via a Unix socket).
- Click any cell → switches to that desktop and closes the HUD.
- There's also a menu bar icon (grid symbol) for manual control, restarting, and opening Accessibility settings.

## Requirements

- macOS 13+
- yabai and skhd (installed via Homebrew, running)
- Accessibility permission (needed for the global hotkey; prompted on first launch)
- A config file at `~/.config/spacemap/config` that declares your grid size (`GRID_COLS` / `GRID_ROWS`) and optional `CELL_STYLE`

## Tech

It's a small Swift/AppKit app (no SwiftUI). The binary is built with Swift Package Manager and packaged as a standard `.app` bundle.
