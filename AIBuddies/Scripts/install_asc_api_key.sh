#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  Scripts/install_asc_api_key.sh <key_id> <issuer_id> <path_to_AuthKey_keyid.p8>

Example:
  Scripts/install_asc_api_key.sh ABCDE12345 00000000-0000-0000-0000-000000000000 ~/Downloads/AuthKey_ABCDE12345.p8
EOF
}

if [[ $# -ne 3 ]]; then
  usage
  exit 64
fi

KEY_ID="$1"
ISSUER_ID="$2"
SOURCE_KEY="${3/#\~/$HOME}"
DEST_DIR="${ASC_PRIVATE_KEYS_DIR:-$HOME/.appstoreconnect/private_keys}"
DEST_FILE="$DEST_DIR/AuthKey_${KEY_ID}.p8"

if [[ ! -f "$SOURCE_KEY" ]]; then
  echo "Private key file not found: $SOURCE_KEY" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

if [[ "$(cd "$(dirname "$SOURCE_KEY")" && pwd)/$(basename "$SOURCE_KEY")" != "$DEST_FILE" ]]; then
  install -m 600 "$SOURCE_KEY" "$DEST_FILE"
else
  chmod 600 "$DEST_FILE"
fi

echo "Installed App Store Connect API key at $DEST_FILE"
echo "Use these environment values if you override the repo defaults:"
echo "export ASC_KEY_ID=$KEY_ID"
echo "export ASC_ISSUER_ID=$ISSUER_ID"
echo "export ASC_KEY_FILEPATH=$DEST_FILE"
