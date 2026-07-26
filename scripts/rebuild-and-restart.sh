#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
configuration=${1:-release}
app_dir="$project_dir/dist/AeroShot.app"
process_name="AeroShot"
bundle_identifier="dev.sanvq.aeroshot"

"$script_dir/build-app.sh" "$configuration"

if pgrep -x "$process_name" >/dev/null; then
    osascript -e "tell application id \"$bundle_identifier\" to quit"

    for _ in {1..50}; do
        if ! pgrep -x "$process_name" >/dev/null; then
            break
        fi
        sleep 0.1
    done

    if pgrep -x "$process_name" >/dev/null; then
        print -u2 "AeroShot did not quit after 5 seconds; not launching a duplicate."
        exit 1
    fi
fi

open "$app_dir"
echo "Restarted $app_dir"
