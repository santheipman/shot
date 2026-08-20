#!/bin/bash
# Allow an SSH session to record this disposable VM's display.
set -euo pipefail

CLIENT="/usr/libexec/sshd-keygen-wrapper"
DB="/Library/Application Support/com.apple.TCC/TCC.db"

sudo sqlite3 "$DB" "INSERT OR REPLACE INTO access \
(service,client,client_type,auth_value,auth_reason,auth_version,csreq,policy_id,\
indirect_object_identifier_type,indirect_object_identifier,indirect_object_code_identity,\
flags,last_modified,pid,pid_version,boot_uuid,last_reminded) VALUES \
('kTCCServiceScreenCapture','$CLIENT',1,2,4,1,NULL,NULL,NULL,'UNUSED',NULL,0,\
strftime('%s','now'),NULL,NULL,'UNUSED',strftime('%s','now'));"

sudo pkill tccd 2>/dev/null || true
