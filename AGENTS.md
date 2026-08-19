- Keep solutions simple. Do not overengineer.
- We and this machine is the only user of this app for now.
- Run `swift test` after code changes.
- After making an app change, rebuild and restart Shot with
  `./scripts/rebuild-and-restart.sh`.

## AeroSpace compatibility

- Do not call AeroSpace APIs.
- Every successful capture creates a new independent `NSPanel` and controller.
  Never reuse, restore, move, or activate an existing editor.
- A new editor becomes the key window without raising an older editor from
  another workspace.
- Closing an editor destroys its panel and controller.
- Do not add `canJoinAllSpaces` to editor panels. Pins intentionally use it to
  follow the user; selection overlays use it to cover every display.
- `CaptureCoordinator` owns live editor controllers and removes them in
  `windowWillClose`.
- With keyboard selection on, the overlay makes the window for the display
  under the pointer key, and retries once after the run loop settles. This
  applies to selection overlays only; never do it for editor panels.

## Keyboard control

See `docs/keyboard.md` before changing the keyboard layer. It records the key
routing order, why the editor has no count prefixes, and why the flipped-axis
handling lives in `KeyboardSelection` rather than at the call site.

Keep these settings in `PreviewWindowController.swift`:

```swift
panel.level = .floating
panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.isRestorable = false
panel.collectionBehavior = [.fullScreenAuxiliary]
```

After changing window creation, lifecycle, activation, or placement, verify:

1. Capture and leave an editor open in one workspace.
2. Switch to another workspace and capture again.
3. Confirm the new editor appears without switching back.
4. Confirm both editors remain independent.
