#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPTIONS="$ROOT_DIR/Scripts/ExportOptions-AppStore.plist"

MAC_ARCHIVE="${MAC_ARCHIVE:-/tmp/AIBuddiesMac.xcarchive}"
IOS_ARCHIVE="${IOS_ARCHIVE:-/tmp/AIBuddiesiOS.xcarchive}"
MAC_EXPORT="${MAC_EXPORT:-/tmp/AIBuddiesMacExport}"
IOS_EXPORT="${IOS_EXPORT:-/tmp/AIBuddiesiOSExport}"

rm -rf "$MAC_EXPORT" "$IOS_EXPORT"
mkdir -p "$MAC_EXPORT" "$IOS_EXPORT"

echo "==> Exporting macOS archive for App Store Connect"
xcodebuild \
  -exportArchive \
  -archivePath "$MAC_ARCHIVE" \
  -exportPath "$MAC_EXPORT" \
  -exportOptionsPlist "$OPTIONS" \
  -allowProvisioningUpdates

echo "==> Exporting iOS archive for App Store Connect"
xcodebuild \
  -exportArchive \
  -archivePath "$IOS_ARCHIVE" \
  -exportPath "$IOS_EXPORT" \
  -exportOptionsPlist "$OPTIONS" \
  -allowProvisioningUpdates

echo "==> Exports created:"
echo "    $MAC_EXPORT"
echo "    $IOS_EXPORT"
