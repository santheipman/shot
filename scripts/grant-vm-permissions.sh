#!/bin/bash
# Run inside shot-golden. The base image has SIP disabled, allowing Shot's
# Screen Recording grant to be prepared for disposable UI tests.
set -euo pipefail

GUEST_USER="${SHOT_VM_USER:-admin}"
SHOT_APP="/Users/$GUEST_USER/Applications/Shot.app"
SYSTEM_TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
NOW='strftime("%s","now")'

[ -d "$SHOT_APP" ] || { echo "Shot.app not found at $SHOT_APP" >&2; exit 1; }

requirement="$(codesign -d -r- "$SHOT_APP" 2>&1 | sed -n 's/^designated => //p')"
[ -n "$requirement" ] || { echo "Could not read Shot's signing requirement" >&2; exit 1; }
csreq -r "=$requirement" -b /tmp/shot.csreq
csreq_hex="$(xxd -p /tmp/shot.csreq | tr -d '\n')"

sudo sqlite3 "$SYSTEM_TCC_DB" "INSERT OR REPLACE INTO access \
(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,\
indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,\
flags,last_modified,pid,pid_version,boot_uuid,last_reminded) VALUES \
('kTCCServiceScreenCapture','dev.sanvq.shot',0,2,4,1,X'$csreq_hex',NULL,NULL,'UNUSED',NULL,0,$NOW,NULL,NULL,'UNUSED',$NOW);"

sudo pkill tccd 2>/dev/null || true
sudo pmset -a sleep 0 displaysleep 0 disksleep 0 2>/dev/null || true
sudo sqlite3 "$SYSTEM_TCC_DB" "SELECT service,client,auth_value FROM access WHERE client = 'dev.sanvq.shot';"
