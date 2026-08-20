#!/bin/bash
# Disposable Tart VM harness for hands-on Shot testing.
set -euo pipefail

GOLDEN="${SHOT_VM_GOLDEN:-shot-golden}"
PLAY_VM="${SHOT_VM_NAME:-shot-play}"
GUEST_USER="${SHOT_VM_USER:-admin}"
GUEST_APP="/Users/$GUEST_USER/Applications/Shot.app"
GUEST_LOG="/tmp/shot.log"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes -o ConnectTimeout=8)
REPO="$(cd "$(dirname "$0")/.." && pwd)"
RECORDINGS_DIR="$REPO/recordings"
TART_BIN="$(command -v tart)"

log() { printf '\033[36m[vm]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31m[vm] %s\033[0m\n' "$*" >&2; exit 1; }

vm_exists() { tart list 2>/dev/null | awk '{print $2}' | grep -qx "$1"; }
vm_ip() { tart ip "$1" 2>/dev/null || true; }
job_label() { echo "dev.sanvq.shot.vm.$1"; }

sh_vm() {
  local ip="$1"
  shift
  ssh "${SSH_OPTS[@]}" "$GUEST_USER@$ip" "$@"
}

down() {
  local name="$1"
  local label
  label="$(job_label "$name")"
  if vm_exists "$name"; then
    tart stop "$name" >/dev/null 2>&1 || true
    for _ in $(seq 1 15); do
      [ "$(tart list 2>/dev/null | awk -v n="$name" '$2==n{print $NF}')" = "stopped" ] && break
      sleep 1
    done
    tart delete "$name" >/dev/null
    log "deleted $name"
  fi
  launchctl remove "$label" >/dev/null 2>&1 || true
}

up() {
  local name="$1"
  vm_exists "$GOLDEN" || die "golden image '$GOLDEN' not found; see scripts/vm-golden.md"
  down "$name" >/dev/null 2>&1 || true
  log "cloning $GOLDEN -> $name"
  tart clone "$GOLDEN" "$name"
  log "booting $name"
  launchctl submit -l "$(job_label "$name")" -- "$TART_BIN" run "$name"

  local ip=""
  for _ in $(seq 1 40); do
    ip="$(vm_ip "$name")"
    if [ -n "$ip" ] && nc -z -w2 "$ip" 22 >/dev/null 2>&1; then
      break
    fi
    sleep 3
  done
  [ -n "$ip" ] || die "$name did not come up"
  sh_vm "$ip" true || die "SSH is not ready on $name"
  log "$name up at $ip"
  echo "$ip"
}

sync_app() {
  local ip="$1"
  log "building Shot.app on the host"
  "$REPO/scripts/build-app.sh" release >/dev/null
  log "copying Shot.app -> $GUEST_APP"
  sh_vm "$ip" "pkill -x Shot 2>/dev/null || true; mkdir -p /Users/$GUEST_USER/Applications; rm -rf '$GUEST_APP'"
  scp "${SSH_OPTS[@]}" -r "$REPO/dist/Shot.app" "$GUEST_USER@$ip:/Users/$GUEST_USER/Applications/Shot.app" >/dev/null
}

launch_app() {
  local ip="$1"
  local action="${2:-}"
  local uid
  uid="$(sh_vm "$ip" 'id -u')"
  local action_command="sudo launchctl asuser $uid launchctl unsetenv SHOT_MANUAL_TEST_ACTION;"
  if [ -n "$action" ]; then
    action_command="sudo launchctl asuser $uid launchctl setenv SHOT_MANUAL_TEST_ACTION '$action';"
  fi
  sh_vm "$ip" "rm -f '$GUEST_LOG'; defaults write dev.sanvq.shot shortcutSetupCompleted -bool true; \
    sudo launchctl asuser $uid launchctl setenv SHOT_EVENT_LOG '$GUEST_LOG'; \
    $action_command \
    sudo launchctl asuser $uid open '$GUEST_APP'; \
    sudo launchctl asuser $uid launchctl unsetenv SHOT_MANUAL_TEST_ACTION"

  for _ in $(seq 1 20); do
    if sh_vm "$ip" "grep -q 'screen_capture_permission' '$GUEST_LOG' 2>/dev/null"; then
      break
    fi
    sleep 1
  done

  local permission
  permission="$(sh_vm "$ip" "grep 'screen_capture_permission' '$GUEST_LOG' 2>/dev/null | tail -1" || true)"
  case "$permission" in
    *granted=true*) log "Shot launched with Screen Recording permission" ;;
    *granted=false*) die "Shot lacks Screen Recording permission; repair shot-golden using scripts/vm-golden.md" ;;
    *) die "Shot launched but did not write its permission status to $GUEST_LOG" ;;
  esac
}

action() {
  local action="${1:-}"
  case "$action" in
    area|pin|text|fullscreen) ;;
    *) die "ACTION must be one of: area, pin, text, fullscreen" ;;
  esac
  vm_exists "$PLAY_VM" || die "VM '$PLAY_VM' is not running"
  local ip
  ip="$(vm_ip "$PLAY_VM")"
  sh_vm "$ip" "pkill -x Shot 2>/dev/null || true"
  launch_app "$ip" "$action"
  log "started '$action' in $PLAY_VM"
}

record() {
  local name="${1:-demo}"
  local seconds="${2:-40}"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "recording NAME may contain only letters, numbers, dots, dashes, and underscores"
  [[ "$seconds" =~ ^[0-9]+$ ]] && [ "$seconds" -ge 1 ] && [ "$seconds" -le 300 ] || die "recording SECONDS must be between 1 and 300"
  vm_exists "$PLAY_VM" || die "VM '$PLAY_VM' is not running"

  local ip stamp remote output
  ip="$(vm_ip "$PLAY_VM")"
  [ -n "$ip" ] || die "could not resolve the IP for '$PLAY_VM'"
  stamp="$(date +%Y%m%d-%H%M%S)"
  remote="/tmp/shot-recording-$stamp.mov"
  output="$RECORDINGS_DIR/$name-$stamp.mov"
  mkdir -p "$RECORDINGS_DIR"

  scp "${SSH_OPTS[@]}" "$REPO/scripts/grant-vm-recording-permission.sh" \
    "$GUEST_USER@$ip:/tmp/grant-shot-recording.sh" >/dev/null
  sh_vm "$ip" "bash /tmp/grant-shot-recording.sh"

  log "recording $PLAY_VM for $seconds seconds"
  log "if macOS asks to bypass the private window picker, click Allow in the guest"
  sh_vm "$ip" "/usr/sbin/screencapture -v -D1 -V$seconds '$remote'"
  scp "${SSH_OPTS[@]}" "$GUEST_USER@$ip:$remote" "$output" >/dev/null
  log "saved $output"
  echo "$output"
}

interactive() {
  local ip
  ip="$(up "$PLAY_VM")"
  sync_app "$ip"
  launch_app "$ip"
  log "VM '$PLAY_VM' is ready for hands-on testing."
  log "Inspect the event log with: make vm-logs"
  log "When finished, delete the clone with: make vm-clean"
}

logs() {
  local ip
  vm_exists "$PLAY_VM" || die "VM '$PLAY_VM' is not running"
  ip="$(vm_ip "$PLAY_VM")"
  [ -n "$ip" ] || die "could not resolve the IP for '$PLAY_VM'"
  sh_vm "$ip" "cat '$GUEST_LOG'"
}

clean() {
  down "$PLAY_VM"
  down shot-run
}

case "${1:-}" in
  interactive) interactive ;;
  action) action "${2:-}" ;;
  record) record "${2:-demo}" "${3:-40}" ;;
  logs) logs ;;
  clean) clean ;;
  up) up "${2:-shot-run}" ;;
  sync)
    name="${2:-shot-run}"
    sync_app "$(vm_ip "$name")"
    ;;
  *) echo "usage: vm.sh {interactive|action <name>|record <name> <seconds>|logs|clean|up <name>|sync <name>}" >&2; exit 2 ;;
esac
