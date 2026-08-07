# Shot

A native macOS screenshot app that works predictably across AeroSpace
workspaces without using AeroSpace APIs. It runs in the menu bar with no Dock
icon and requires macOS 13 or newer.

## Use

- **Command–Shift–3** captures the display containing the pointer.
- **Command–Shift–4** captures a selected area.
- **Command–Shift–2** captures an area as a floating pin that follows you
  between workspaces.

Area capture freezes the screen before showing the selector, so hover menus,
tooltips, and other temporary UI remain visible while you drag over them.

The editor supports Pencil (**P**), Rectangle (**R**), Arrow (**A**), Text
(**T**), and undo (**Command–Z**). **Escape** commits active text; otherwise it
copies the image and closes the editor. **S** or **Save** writes a PNG to
`~/Documents/screenshot` without closing it. Closing the window does not copy.

Pins can be moved and resized. Hover over a pin to show its close button.

## Build and run

```sh
./scripts/build-app.sh release
open dist/Shot.app
```

To rebuild and restart the running app:

```sh
./scripts/rebuild-and-restart.sh
```

Both scripts accept `debug` instead of `release`. The app bundle is written to
`dist/Shot.app`.

### Code signing

Builds use the identity in `.signing/` when it exists. Keep this directory in
place and do not commit it. Changing the signing identity can make macOS forget
the app's Screen Recording permission and produce black captures.

Create the local identity once on a new machine:

```sh
./scripts/create-local-signing-identity.sh
```

After the first launch, enable Shot in **System Settings → Privacy &
Security → Screen & System Audio Recording**, then restart the app.

If the project moves, update the keychain search path:

```sh
security list-keychains -d user -s \
  "/absolute/path/to/shot/.signing/Shot.keychain-db" \
  "$HOME/Library/Keychains/login.keychain-db"
```

To use another identity:

```sh
SHOT_CODESIGN_IDENTITY='Apple Development: Name' \
  ./scripts/build-app.sh release
```

## Rules that must not change

- Every successful capture creates a new `NSPanel` and controller that own
  their image.
- Never reuse, restore, move, or activate an existing editor.
- A new editor becomes the key window without raising an older editor from
  another workspace.
- Closing an editor destroys its panel and controller.
- Let AppKit and the window manager place windows. Do not call AeroSpace APIs.
- Do not add `canJoinAllSpaces` to editor panels. Pin panels intentionally use
  it to follow the user; selection overlays use it to cover every display.

Keep these settings in `PreviewWindowController.swift`:

```swift
panel.level = .floating
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.isRestorable = false
panel.collectionBehavior = [.fullScreenAuxiliary]
```

`CaptureCoordinator` owns live editor controllers by window number and removes
them in `windowWillClose`.

## Window lifecycle tests

```sh
swift test
```

Also verify workspace placement manually:

1. Capture and leave an editor open in one workspace.
2. Switch to another workspace and capture again.
3. Confirm the new editor appears without switching back.
4. Confirm both editors remain independent.
