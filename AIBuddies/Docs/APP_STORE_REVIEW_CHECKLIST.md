# App Store Review Checklist

Use this as a private release checklist. Keep account-specific IDs, contact
details, review submission IDs, and App Store Connect state out of public commits.

## Gates

| Gate | Status | Evidence / action |
| --- | --- | --- |
| Builds uploaded and attached | Pending | Verify current iOS and macOS builds in App Store Connect |
| Screenshots | Pending | Verify required device sizes and locales |
| Localized product metadata | Pending | Upload and review names, subtitles, descriptions, keywords, URLs, and release notes |
| App Review contact/notes | Pending | Provide current contact details and any reviewer instructions |
| Category, age rating, content rights | Pending | Confirm all compliance answers |
| Export compliance | Pending | Confirm encryption answer for each build |
| App Privacy | Pending | Publish accurate App Privacy answers before review submission |
| Price schedule | Pending | Confirm price tiers and territory availability |
| Local validation | Pending | Run `Scripts/release_gate.sh --unsigned-only` |
| Final App Review submission | Pending | Submit only with explicit action-time approval |

## Conservative Defaults

- Price: free unless monetization is implemented and reviewed.
- Privacy: the app should not collect source code, prompts, or conversation logs.
- Accessibility: do not overclaim support. Publish only features verified by a real accessibility audit.
- App Store Connect API keys: store locally only; never commit `.p8` files or raw key contents.
