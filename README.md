# AeroPeek

A small native macOS overlay that shows which applications and windows live in
each AeroSpace workspace.

Hold **Control–Option–Space** to show the overview. Release the shortcut to hide
it. The app lives in the menu bar and has no Dock icon.

To pin the overview, keep Control–Option held and double-tap Space within
approximately 400 milliseconds. Press Control–Option–Space once more to dismiss
the pinned overlay.

By default, the overview shows workspaces that contain windows, plus the
currently focused or visible workspace. Persistent empty workspaces are omitted.
Use **Show Preview** and **Hide Preview** from the menu-bar icon to pin the
overlay while inspecting it or taking a screenshot.

The focused workspace also shows its current AeroSpace binding mode, container
layout, monitor number, window count, and application count.

## Build and run

Requirements:

- macOS 13 or newer
- AeroSpace
- Xcode command-line tools

```sh
./scripts/build-app.sh
open ".build/AeroPeek.app"
```

The shortcut uses macOS's native global-hotkey registration and does not require
Accessibility permission. If another application has already reserved the same
shortcut, change it using the configuration below or select **Retry Shortcut
Registration** from the menu-bar icon after resolving the conflict.

To install it in your user Applications folder:

```sh
./scripts/install.sh
open "$HOME/Applications/AeroPeek.app"
```

Add it to **System Settings → General → Login Items** if you want it to launch
when you sign in.

## App icon

The 1024px source artwork lives at
`Resources/AppIcon/AeroPeek-1024.png`. Regenerate the macOS icon bundle after
changing it:

```sh
./scripts/generate-icon.py
```

Icon generation requires Python 3 and Pillow.

The earlier muted tiled-eye concept is kept at
`Resources/AppIcon/AeroPeek-subtle-1024.png`.

## Change the shortcut

Copy `config.example.json` to:

```text
~/.config/aeropeek/config.json
```

Supported modifier names are `command`, `control`, `option`, and `shift`.
`keyCode` is the macOS hardware key code; `49` is Space. Quit and reopen the app
after changing the shortcut.

Do not assign the same shortcut to AeroSpace itself—the helper needs to receive
both the key-down and key-up events.
