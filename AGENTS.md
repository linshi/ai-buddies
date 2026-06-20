## Project instructions

build mac/ios app as my AI buddies of claude and codex etc, to know the real time usage details and tips

## App Store Connect automation

This open-source repo must not contain a real Apple account, App Store Connect
key id, issuer id, private key path, or `.p8` contents.

For local submission automation, set these environment variables in your own
shell or private `.env` file:

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_KEY_FILEPATH`
- `ASC_APP_ID`
- `FASTLANE_APPLE_ID`
- `FASTLANE_APP_IDENTIFIER`

Do not copy, print, commit, or store the raw `.p8` private key contents in chat or memory. The key file should stay local with owner-only permissions.

Before any App Store Connect automation, verify credentials with:

```bash
cd AIBuddies
Scripts/asc_api_check.rb
```

This key may be used for read-only checks, metadata uploads, build uploads, and submission preparation. Final App Review submission and destructive/account-level actions still require explicit action-time user confirmation unless the current task explicitly grants that final action.
