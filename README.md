# Shot

A native macOS menu-bar screenshot app.

## Features

- **Command–Shift–1** captures an area and extracts editable text with OCR.
- **Command–Shift–2** captures an area as a movable, resizable floating pin.
- **Command–Shift–3** captures the display containing the pointer.
- **Command–Shift–4** captures an area and opens the image editor.
- Editor shortcuts: **P** Pencil, **R** Rectangle, **A** Arrow, **T** Text,
  **Command–Z** Undo, **S** Save, and **Escape** Copy and close.

## Install

Build Shot from source on your Mac.

Prerequisite: Xcode Command Line Tools.

```sh
xcode-select --install
```

Clone, build, and open Shot:

```sh
git clone https://github.com/santheipman/shot.git
cd shot
./scripts/build-app.sh release
open dist/Shot.app
```

The app is built at `dist/Shot.app`. On first launch, allow Shot under **System
Settings → Privacy & Security → Screen Recording** (or **Screen & System Audio
Recording**), then restart it:

```sh
./scripts/rebuild-and-restart.sh
```

## Contribution

Tell your coding agent what you want to change.
