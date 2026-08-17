#!/bin/zsh

set -euo pipefail

bundle_identifier="dev.sanvq.shot"
flag="shortcutSetupCompleted"

if /usr/bin/defaults read "$bundle_identifier" "$flag" >/dev/null 2>&1; then
    /usr/bin/defaults delete "$bundle_identifier" "$flag"
    echo "Reset Shot's first-launch setup."
else
    echo "Shot's first-launch setup is already reset."
fi
