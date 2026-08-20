- Keep solutions simple. Do not overengineer.
- We and this machine is the only user of this app for now.
- `README.md` is for Shot users. Keep agent-only and internal development
  workflows in `AGENTS.md` or focused developer documentation.
- Treat this repository as public. Never commit or push personal or sensitive
  information, credentials, private identifiers, logs, screenshots, or
  recordings. Check staged changes and new files before committing or pushing.
- Run `swift test` after code changes.
- After making an app change, rebuild and restart Shot with
  `./scripts/rebuild-and-restart.sh`.
- When the user explicitly asks for a manual test, use the disposable Tart VM:
  `make vm`. Exercise the changed behavior in `shot-play`, inspect
  `make vm-logs`, report what passed or failed, then run `make vm-clean`.
  Setup and internals: `scripts/vm-golden.md`.
- Only record a VM demo when the user explicitly asks. Use
  `make vm-record NAME=feature SECONDS=40`; recordings go to the git-ignored
  `recordings/` directory.

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
