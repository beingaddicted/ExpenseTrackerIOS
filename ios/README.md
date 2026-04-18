# Expense Tracker (iOS)

Native **SwiftUI** app with **SwiftData** and **App Intents**: parses the same combined bank-SMS text as the PWA ([`js/sms-parser.js`](../js/sms-parser.js)), without Scriptable.

## Requirements

- macOS with **Xcode 15+**
- **iOS 17+** device or simulator
- Apple ID / development team for code signing

## Open the project

```bash
open ios/ExpenseTracker.xcodeproj
```

1. Select the **ExpenseTracker** target → **Signing & Capabilities** → choose your **Team**.
2. Build and run (`⌘R`).

## Importing SMS

iOS does **not** allow reading the SMS inbox from this app. Flow:

1. **Build a Shortcut** (or adapt the existing one): **Find Messages** → **Repeat** / combine bodies with **`===SMS===`** between messages (same as [`BankSMS.js`](../data/ShortCuts/BankSMS.js)).
2. Add **Expense Tracker → Import bank SMS batch** and pass the combined text into **Combined SMS text**.
3. The intent parses and saves transactions into SwiftData (same delimiter and parsing rules as the web app, minus the full [`sms-templates.js`](../js/sms-templates.js) registry — HDFC UPI pipe patterns are included in-app via [`SMSMiniTemplates.swift`](ExpenseTracker/SMSMiniTemplates.swift)).

You can also **paste** combined text on the main screen and tap **Import**.

## Parser parity

- **Included:** Generic rules from `sms-parser.js`, mini HDFC structured templates, chunk splitting aligned with `BankSMS.js`.
- **Not bundled:** Every entry in `sms-templates.js`. Extend [`SMSMiniTemplates.swift`](ExpenseTracker/SMSMiniTemplates.swift) or add Swift templates as needed.

## PWA

The progressive web app remains in the repo root; this folder is the optional native client.
