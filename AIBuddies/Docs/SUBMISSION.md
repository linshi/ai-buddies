# App Store Submission Guide

This guide is intentionally account-neutral. Do not commit real Apple account
emails, App Store Connect key IDs, issuer IDs, private key paths, `.p8` files,
team IDs, or App Store app IDs to this repository.

## Local Apple Setup

Update `Config.xcconfig` with your own identifiers:

```xcconfig
DEVELOPMENT_TEAM = YOURTEAMID
APP_BUNDLE_ID_MAC = com.yourcompany.aibuddies
APP_BUNDLE_ID_IOS = com.yourcompany.aibuddies
APP_BUNDLE_ID_WIDGETS = com.yourcompany.aibuddies.widgets
```

Update these files to match the same identifiers:

- `Apps/AIBuddiesMac/AIBuddiesMac.entitlements`
- `Apps/AIBuddiesiOS/AIBuddiesiOS.entitlements`
- `Apps/AIBuddiesWidgets/AIBuddiesWidgets.entitlements`
- `Shared/Constants.swift`
- `fastlane/Appfile` or the `FASTLANE_APP_IDENTIFIER` environment variable

## App Store Connect API

Set credentials locally, outside the repo:

```bash
export ASC_KEY_ID=YOUR_KEY_ID
export ASC_ISSUER_ID=YOUR_ISSUER_ID
export ASC_APP_ID=YOUR_APP_STORE_CONNECT_APP_ID
export ASC_KEY_FILEPATH="$HOME/.appstoreconnect/private_keys/AuthKey_YOUR_KEY_ID.p8"
export FASTLANE_APPLE_ID="you@example.com"
export FASTLANE_APP_IDENTIFIER="com.yourcompany.aibuddies"
```

Install or repair the downloaded `.p8` file:

```bash
cd AIBuddies
Scripts/install_asc_api_key.sh "$ASC_KEY_ID" "$ASC_ISSUER_ID" /path/to/AuthKey_YOUR_KEY_ID.p8
```

Verify credentials without changing App Store Connect:

```bash
Scripts/asc_api_check.rb
```

## Build And Submit

Regenerate the Xcode project anytime:

```bash
cd AIBuddies
xcodegen generate
```

Run the local gate without signing:

```bash
Scripts/release_gate.sh --unsigned-only
```

Run fastlane metadata/build lanes after your Apple account setup is complete:

```bash
fastlane ios metadata
fastlane mac metadata
fastlane ios release
fastlane mac release
```

The fastlane lanes keep `submit_for_review: false`. Final App Review submission
should remain an explicit action-time decision.
