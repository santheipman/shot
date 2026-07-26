# AeroShot

AeroShot is a small native macOS screenshot app designed primarily to behave
predictably with the AeroSpace window manager. Its window lifecycle is kept
independent of AeroSpace APIs so the same behavior works with other macOS
window managers.

Press **Command–Shift–3** to capture the display containing the pointer, or
**Command–Shift–4** and drag an area. AeroShot opens the captured image
in a floating annotation editor in the currently focused AeroSpace workspace.
Draw with Pencil, Rectangle, or Arrow, and choose from six colors and three
line thicknesses. **Command–Z** undoes the last annotation. Press **Escape** to
copy the flattened image to the clipboard and close the editor. **Save** writes
a timestamped PNG directly to `~/Documents/screenshot` and keeps the editor
open. In the editor, press **P** for Pencil, **R** for Rectangle, **A** for
Arrow, or **S** to save. Closing with the window control does not copy. The
menu-bar item also has matching capture commands.

Press **Command–Shift–2** and drag an area to pin it. Each pin is an independent,
borderless image card that floats above normal windows and follows you between
workspaces. Drag a pin to move it, resize it from an edge or corner, or hover
over it to reveal its close button. Pins preserve the image aspect ratio and do
not edit, save, or copy the image.

## Rules that must not change

AeroShot exists because other screenshot apps can activate an editor tied to a
different workspace. Preserve these rules when adding features:

- Every successful capture creates and presents a new `NSPanel`.
- Each panel owns the image from its corresponding capture.
- AeroShot never reuses, restores, moves, or explicitly activates an existing
  editor.
- A newly presented editor becomes the active key window without raising an
  older editor from another workspace.
- Closing a panel destroys that panel and its controller.
- Multiple captures can have independent panels in different workspaces.
- The panel floats through AppKit. AeroSpace needs no app-specific rule.
- Do not add `canJoinAllSpaces` to editor panels. Pin panels intentionally use
  it so they follow the user between workspaces. The selection overlays use it
  because they must cover every display during selection.

The important editor settings are in
`Sources/AeroShot/PreviewWindowController.swift`:

```swift
panel.level = .floating
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.isRestorable = false
panel.collectionBehavior = [.fullScreenAuxiliary]
```

`CaptureCoordinator` owns live editor controllers in a dictionary keyed by
window number. `windowWillClose` removes the controller. This ownership is what
prevents hidden or reused editor windows.

AeroShot does not assign windows to AeroSpace workspaces. It creates a fresh
window in the current macOS desktop context and leaves placement to the window
manager. The lifecycle rules above are the part AeroShot controls and tests.

## Current features

- Area selection on one or more displays
- Native screen capture at the selected coordinates
- A new floating annotation editor for every capture
- Multiple movable and resizable image pins that follow between workspaces
- Pencil, rectangle, and arrow annotations
- Red, yellow, green, blue, black, and white annotation colors
- Thin, medium, and thick annotation strokes
- Undo the most recent annotation with Command–Z
- Select Pencil with P, Rectangle with R, or Arrow with A
- Copy and close with Escape
- Save with S or the Save button without closing
- Menu-bar app with no Dock icon

## Project map

- `Sources/AeroShot/AppDelegate.swift` — menu-bar UI, global shortcut, startup
- `Sources/AeroShot/GlobalHotKey.swift` — Carbon global hotkey registration
- `Sources/AeroShot/SelectionOverlay.swift` — drag-selection overlays and
  AppKit-to-Quartz coordinate conversion
- `Sources/AeroShot/ScreenCapture.swift` — permission check and pixel capture
- `Sources/AeroShot/CaptureCoordinator.swift` — capture and editor lifecycle
- `Sources/AeroShot/EditorWindow.swift` — editor lifecycle boundary used by
  production windows and tests
- `Sources/AeroShot/PinWindow.swift` — pin lifecycle boundary used by
  production windows and tests
- `Sources/AeroShot/PinWindowController.swift` — borderless floating pin UI
- `Sources/AeroShot/AnnotationEditor.swift` — annotation model, geometry, and
  native-resolution export rendering
- `Sources/AeroShot/PreviewWindowController.swift` — floating editor UI,
  Escape-to-copy, direct save, and close lifecycle
- `Sources/AeroShot/EventLog.swift` — optional lifecycle diagnostics
- `Sources/AeroShot/ImageDiagnostics.swift` — black-image detection used only
  when file logging is enabled
- `Tests/AeroShotTests/CaptureCoordinatorTests.swift` — independent editor
  lifecycle tests
- `Resources/Info.plist` — bundle identity and macOS app settings
- `scripts/build-app.sh` — builds, bundles, and signs the app
- `scripts/create-local-signing-identity.sh` — one-time local signing setup

The app requires macOS 13 or newer. It is a Swift Package executable wrapped in
an app bundle by the build script.

## Build and run

From the project root:

```sh
./scripts/build-app.sh release
open dist/AeroShot.app
```

The generated app is `dist/AeroShot.app`. `.build/` and `dist/` are disposable
generated directories.

Normal development builds use the stable identity stored in `.signing/`.
Do not delete, replace, move separately, or commit this directory. macOS Screen
Recording permission follows the app's bundle identifier and code-signing
requirement. Ad-hoc signing each build can make macOS treat the rebuilt app as
a different app and return black captures.

If `.signing/` does not exist on a new machine, create it once:

```sh
./scripts/create-local-signing-identity.sh
```

This creates:

- `.signing/AeroShot.keychain-db`
- `.signing/keychain-password`
- a local identity named `AeroShot Local Development`

The script adds that keychain's absolute path to the user's keychain search
list. If the project directory moves, replace the old path in this list:

```sh
security list-keychains -d user
security list-keychains -d user -s \
  "/absolute/path/to/aeroshot/.signing/AeroShot.keychain-db" \
  "$HOME/Library/Keychains/login.keychain-db"
```

After the first signed launch, enable AeroShot in **System Settings → Privacy &
Security → Screen & System Audio Recording**, quit it, and relaunch it. Avoid
resetting this permission during ordinary builds.

To use a different signing identity:

```sh
AEROSHOT_CODESIGN_IDENTITY='Apple Development: Name' \
  ./scripts/build-app.sh release
```

## Window lifecycle tests

Run the automated tests with:

```sh
swift test
```

The tests verify the AeroShot behavior that allows it to work predictably with
AeroSpace: every capture gets a distinct editor, existing editors are not
presented again, editors close independently, closing all editors releases all
live windows, and capture failures create no editor.

The exact workspace placement remains a short manual AeroSpace smoke test:

1. Capture and leave an editor open in one workspace.
2. Switch to another workspace and capture again.
3. Confirm the new editor appears without returning focus to the first editor's
   workspace.
4. Switch between the workspaces and confirm both editors remain independent.

## Editor architecture

Each editor owns its captured source image, ordered annotations, and canvas.
The canvas maps pointer input into source-image coordinates, so annotations
remain aligned when the panel is resized. Clipboard and PNG exports flatten at
the source image's backing-pixel resolution.

Keep this state per editor. Do not introduce a shared singleton editor, reopen
a closed window, or activate an editor from a previous workspace.
