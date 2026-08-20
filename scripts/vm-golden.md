# Tart VM setup

`make vm` clones a frozen VM named `shot-golden`. Create it once, grant Shot
Screen Recording permission, then keep it stopped. Test runs use disposable
clones and never modify the golden image.

## Prerequisites

- Apple Silicon Mac.
- Tart installed with `brew install cirruslabs/cli/tart`.
- A base image named `sequoia-base`:

  ```sh
  tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest sequoia-base
  ```

The base image login is `admin` / `admin`.

## Create `shot-golden`

```sh
tart clone sequoia-base shot-golden
tart run shot-golden
```

Leave the VM window open. From the host, configure passwordless SSH:

```sh
ssh-keygen -R "$(tart ip shot-golden)"
ssh-copy-id -o StrictHostKeyChecking=accept-new admin@"$(tart ip shot-golden)"
```

Build Shot and install the initial copy at its permanent guest path:

```sh
./scripts/build-app.sh release
ssh admin@"$(tart ip shot-golden)" 'mkdir -p ~/Applications'
scp -r dist/Shot.app admin@"$(tart ip shot-golden)":~/Applications/Shot.app
```

Grant Screen Recording permission to Shot:

```sh
scp scripts/grant-vm-permissions.sh admin@"$(tart ip shot-golden)":~/grant-vm-permissions.sh
ssh admin@"$(tart ip shot-golden)" 'bash ~/grant-vm-permissions.sh'
```

The permission follows Shot's bundle identifier and local signing certificate.
Later builds keep the grant as long as they use the same signing identity.

Freeze the golden image:

```sh
ssh admin@"$(tart ip shot-golden)" 'sudo shutdown -h now'
```

Do not boot `shot-golden` for testing. If Shot's local signing certificate is
replaced, repeat the permission step or recreate the golden image.

## Manual testing

```sh
make vm        # boot shot-play with the latest Shot.app
make vm-action ACTION=area  # start a capture when host shortcuts intercept it
make vm-record NAME=area-demo SECONDS=40  # save a guest display recording
make vm-logs   # inspect Shot's event log
make vm-clean  # delete shot-play
```

`make vm` fails early if the guest does not recognize Shot's Screen Recording
grant. The VM remains open after a successful launch so Shot can be exercised
with real mouse, keyboard, clipboard, window, and capture behavior.

`vm-action` accepts `area`, `pin`, `text`, or `fullscreen`. It is useful for
agent-driven testing because the host macOS owns screenshot shortcuts before
Tart can forward them to the guest. The action uses Shot's normal capture
coordinator; only the trigger differs.

Only record when the user explicitly asks for a video. `vm-record` records the
running guest display and saves a timestamped `.mov` under `recordings/`. Git
ignores that directory. Keep the command running while operating Tart from
another terminal or agent tool. The first recording in a disposable clone may
show a macOS consent dialog; click **Allow** in the guest.
