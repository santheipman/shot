# AeroShot

AeroShot is a small native macOS screenshot app designed primarily to behave
predictably with the AeroSpace window manager. Its window lifecycle is kept
independent of AeroSpace APIs so the same behavior works with other macOS
window managers.

Press **Control–Shift–4**, drag an area, and AeroShot opens the captured image
in a floating panel in the currently focused AeroSpace workspace. The menu-bar
item also has a **Capture Area** command.

## Rules that must not change

AeroShot exists because other screenshot apps can activate an editor tied to a
different workspace. Preserve these rules when adding features:

- Every successful capture creates and presents a new `NSPanel`.
- Each panel owns the image from its corresponding capture.
- AeroShot never reuses, restores, moves, or explicitly activates an existing
  editor.
- Presenting a new editor does not force application-wide activation.
- Closing a panel destroys that panel and its controller.
- Multiple captures can have independent panels in different workspaces.
- The panel floats through AppKit. AeroSpace needs no app-specific rule.
- Do not add `canJoinAllSpaces` to editor panels. The selection overlays use it
  only because they must cover every display during selection.

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
- A new floating preview for every capture
- Copy image to the clipboard
- Save as PNG
- Close with the button or Escape
- Menu-bar app with no Dock icon

There are no annotation tools yet. The next feature work can turn the preview
into an editor, but it should keep the window lifecycle above.

## Project map

- `Sources/AeroShot/AppDelegate.swift` — menu-bar UI, global shortcut, startup
- `Sources/AeroShot/GlobalHotKey.swift` — Carbon global hotkey registration
- `Sources/AeroShot/SelectionOverlay.swift` — drag-selection overlays and
  AppKit-to-Quartz coordinate conversion
- `Sources/AeroShot/ScreenCapture.swift` — permission check and pixel capture
- `Sources/AeroShot/CaptureCoordinator.swift` — capture and editor lifecycle
- `Sources/AeroShot/EditorWindow.swift` — editor lifecycle boundary used by
  production windows and tests
- `Sources/AeroShot/PreviewWindowController.swift` — floating preview UI,
  copy, save, and close
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

## Adding editor features

Keep the captured source image owned by one editor window. A useful next split
is:

- an editor model containing the source image and ordered edits;
- a canvas view that renders the source plus edits;
- tools that add or change edits without knowing about AeroSpace;
- export code that renders the final image for Copy and Save.

Start with one tool and keep Copy and Save working after every step. Add
automated tests for edit rendering separately from the window lifecycle tests.
Then run the manual AeroSpace smoke test for changes that affect window
presentation.

Do not solve editing by introducing a shared singleton editor, reopening a
closed window, or activating an editor from a previous workspace.
