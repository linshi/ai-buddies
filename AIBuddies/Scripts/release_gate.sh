#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/AIBuddies.xcodeproj"
TEAM_ID="${DEVELOPMENT_TEAM:-}"

usage() {
  cat <<'USAGE'
Usage: Scripts/release_gate.sh [--unsigned-only]

Runs the AI Buddies release gate:
  1. Regenerate the Xcode project from project.yml
  2. Run UsageCore tests
  3. Build unsigned Release artifacts for macOS and iOS
  4. Unless --unsigned-only is passed, attempt signed archives with Apple-managed provisioning

Environment:
  DEVELOPMENT_TEAM   Apple Developer Team ID. Required for signed archive checks.
USAGE
}

unsigned_only=0
if [[ "${1:-}" == "--unsigned-only" ]]; then
  unsigned_only=1
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
elif [[ $# -gt 0 ]]; then
  usage >&2
  exit 2
fi

cd "$ROOT_DIR"

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Running UsageCore tests"
swift test --package-path "$ROOT_DIR/Packages/UsageCore"

echo "==> Building macOS Release without signing"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme AIBuddiesMac \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath /tmp/AIBuddiesDD-mac-unsigned \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> Building iOS Release without signing"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme AIBuddiesiOS \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath /tmp/AIBuddiesDD-ios-unsigned \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ "$unsigned_only" == "1" ]]; then
  echo "==> Unsigned release gate passed"
  exit 0
fi

echo "==> Archiving macOS with Apple-managed signing (team: $TEAM_ID)"
if [[ -z "$TEAM_ID" ]]; then
  echo "DEVELOPMENT_TEAM is required for signed archive checks. Re-run with --unsigned-only or set DEVELOPMENT_TEAM." >&2
  exit 2
fi
rm -rf /tmp/AIBuddiesMac.xcarchive /tmp/AIBuddiesDD-mac-signed
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme AIBuddiesMac \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath /tmp/AIBuddiesMac.xcarchive \
  -derivedDataPath /tmp/AIBuddiesDD-mac-signed \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  archive

echo "==> Archiving iOS with Apple-managed signing (team: $TEAM_ID)"
rm -rf /tmp/AIBuddiesiOS.xcarchive /tmp/AIBuddiesDD-ios-signed
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme AIBuddiesiOS \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath /tmp/AIBuddiesiOS.xcarchive \
  -derivedDataPath /tmp/AIBuddiesDD-ios-signed \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  archive

echo "==> Signed release archives created:"
echo "    /tmp/AIBuddiesMac.xcarchive"
echo "    /tmp/AIBuddiesiOS.xcarchive"
