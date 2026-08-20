# Shot

A minimal, native macOS screenshot app that works locally. Capture and edit with
a few keystrokes.

## Features

- **Command–Shift–1** captures an area and extracts editable text with OCR.
- **Command–Shift–2** captures an area as a movable, resizable floating pin.
- **Command–Shift–3** captures the display containing the pointer.
- **Command–Shift–4** captures an area and opens the image editor.
- The editor opens with Rectangle selected. Use **V** Select, **P** Pencil,
  **R** Rectangle, **L** Line, **D** Dashed Line, **A** Arrow, or **T** Text.
  Selected annotations can be moved or deleted.
- Editor shortcuts: **Command–Z** Undo, **Command–Shift–Z** Redo, **Delete**
  Remove selected annotation, **S** Save, and **Escape** Deselect or Copy and
  close.

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

## Trust and privacy

- Shot works locally with no network requests, analytics, updater, or remote
  dependencies. OCR uses Apple Vision on your Mac.
- Shot only asks for screen-recording permission. Source builds are locally
  signed, but not Apple-notarized or protected by macOS App Sandbox.

## Contribution

Clone this repository, tell your coding agent what you want to change, and
maintain your own version of Shot.
