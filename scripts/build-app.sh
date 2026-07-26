#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
configuration=${1:-release}
output_dir="$project_dir/dist"
app_dir="$output_dir/AeroShot.app"
codesign_identity=${AEROSHOT_CODESIGN_IDENTITY:--}
codesign_keychain=${AEROSHOT_CODESIGN_KEYCHAIN:-}
codesign_password_file=${AEROSHOT_CODESIGN_PASSWORD_FILE:-}
local_keychain="$project_dir/.signing/AeroShot.keychain-db"
local_password_file="$project_dir/.signing/keychain-password"
restore_keychain_search=false
original_keychains=()

function restore_keychains() {
    if [[ "$restore_keychain_search" == true ]]; then
        security list-keychains -d user -s "${original_keychains[@]}"
        restore_keychain_search=false
    fi
}

trap restore_keychains EXIT
swiftpm_cache="/private/tmp/aeroshot-swiftpm-cache"
swiftpm_config="/private/tmp/aeroshot-swiftpm-config"
swiftpm_security="/private/tmp/aeroshot-swiftpm-security"
clang_cache="/private/tmp/aeroshot-clang-module-cache"

mkdir -p "$swiftpm_cache" "$swiftpm_config" "$swiftpm_security" "$clang_cache"

if [[ "$codesign_identity" == "-" && -f "$local_keychain" ]]; then
    codesign_identity="AeroShot Local Development"
    codesign_keychain="$local_keychain"
    codesign_password_file="$local_password_file"
fi

cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$clang_cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$clang_cache"

swift_args=(
    --disable-sandbox
    --cache-path "$swiftpm_cache"
    --config-path "$swiftpm_config"
    --security-path "$swiftpm_security"
    --scratch-path "$project_dir/.build"
)

swift build "${swift_args[@]}" -c "$configuration"

binary_dir=$(swift build "${swift_args[@]}" -c "$configuration" --show-bin-path)
mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp "$binary_dir/AeroShot" "$app_dir/Contents/MacOS/AeroShot"
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"

codesign_args=(--force --deep --sign "$codesign_identity")
if [[ -n "$codesign_keychain" ]]; then
    if [[ -n "$codesign_password_file" ]]; then
        keychain_password=$(<"$codesign_password_file")
        security unlock-keychain -p "$keychain_password" "$codesign_keychain"
    fi

    original_keychains=(
        "${(@f)$(security list-keychains -d user |
            /usr/bin/sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')}"
    )
    security list-keychains -d user -s \
        "$codesign_keychain" \
        "${original_keychains[@]}"
    restore_keychain_search=true

    identity_hash=$(security find-identity -v -p codesigning "$codesign_keychain" |
        awk -v name="\"$codesign_identity\"" '$0 ~ name { print $2; exit }')
    if [[ -z "$identity_hash" ]]; then
        print -u2 "Could not find code-signing identity: $codesign_identity"
        exit 1
    fi
    codesign_args=(--force --deep --sign "$identity_hash")
fi
codesign "${codesign_args[@]}" "$app_dir"
restore_keychains
echo "$app_dir"
