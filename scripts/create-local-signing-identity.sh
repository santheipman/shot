#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
signing_dir="$project_dir/.signing"
keychain_path="$signing_dir/Shot.keychain-db"
password_file="$signing_dir/keychain-password"
identity_name="Shot Local Development"
openssl_config="$project_dir/Resources/LocalCodeSigning.openssl.cnf"
temporary_dir=$(mktemp -d /private/tmp/shot-signing.XXXXXX)

function cleanup() {
    rm -rf "$temporary_dir"
}

trap cleanup EXIT

if [[ -e "$keychain_path" || -e "$password_file" ]]; then
    print -u2 "Shot signing files already exist at $signing_dir"
    print -u2 "Refusing to overwrite a signing identity."
    exit 1
fi

mkdir -p "$signing_dir"
chmod 700 "$signing_dir"

keychain_password=$(/usr/bin/openssl rand -hex 24)
p12_password=$(/usr/bin/openssl rand -hex 24)
print -rn -- "$keychain_password" > "$password_file"
chmod 600 "$password_file"

/usr/bin/openssl req \
    -x509 \
    -newkey rsa:2048 \
    -sha256 \
    -days 3650 \
    -nodes \
    -config "$openssl_config" \
    -keyout "$temporary_dir/private-key.pem" \
    -out "$temporary_dir/certificate.pem"

/usr/bin/openssl pkcs12 \
    -export \
    -name "$identity_name" \
    -inkey "$temporary_dir/private-key.pem" \
    -in "$temporary_dir/certificate.pem" \
    -out "$temporary_dir/identity.p12" \
    -passout "pass:$p12_password"

/usr/bin/security create-keychain -p "$keychain_password" "$keychain_path"
/usr/bin/security set-keychain-settings -lut 21600 "$keychain_path"
/usr/bin/security unlock-keychain -p "$keychain_password" "$keychain_path"
/usr/bin/security import "$temporary_dir/identity.p12" \
    -k "$keychain_path" \
    -P "$p12_password" \
    -T /usr/bin/codesign
/usr/bin/security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$keychain_password" \
    "$keychain_path"
/usr/bin/security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$keychain_path" \
    "$temporary_dir/certificate.pem"

# Keep the isolated keychain in the user search list so macOS can resolve the
# certificate trust when Shot runs. The private key remains protected by
# the project-local keychain password and its codesign-only access control.
user_keychains=(
    "${(@f)$(/usr/bin/security list-keychains -d user |
        /usr/bin/sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//')}"
)
/usr/bin/security list-keychains -d user -s \
    "$keychain_path" \
    "${user_keychains[@]}"

print -r -- "Created local identity:"
/usr/bin/security find-identity -v -p codesigning "$keychain_path"
