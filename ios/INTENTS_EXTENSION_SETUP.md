# Setup paths

There are two ways to run this app, depending on what kind of Apple ID
you sign with. Pick the right one for your situation — they don't mix.

| Apple ID type | Path | Result |
| --- | --- | --- |
| **Free** (personal Apple ID, sideload via Xcode, 7-day re-sign) | **A** | Works. Uses the App Intent in the main app. |
| **Paid** ($99/year Developer Program) | **B** | Better. Adds a Custom INIntent extension and App Groups, eliminating the per-call privacy prompt. |

---

## Path A — Free Apple ID (the most common case)

App Groups, custom entitlements, and most extensions that share storage
with the main app are paid-account-only. So you skip the extension target
entirely and rely on the in-app App Intent.

### What the app uses on this path

- `Intents/ImportBankSMSBatchIntent.swift` — the App Intent. Receives
  combined SMS text from the Shortcut and parses + saves it directly
  in the main app's process.
- `Intents/GetImportStartDateIntent.swift` — returns the day count.
- `UserDefaults.standard` (via the `AppGroup.defaults` shim — falls
  back automatically when the App Group entitlement is missing).
- The SwiftData store in the app's own sandbox (Persistence.swift
  also falls back automatically).

### Skip these in Xcode

- Don't add the Intents Extension target.
- Don't enable the **App Groups** capability.
- Don't set `CODE_SIGN_ENTITLEMENTS = ExpenseTracker/ExpenseTracker.entitlements`
  on the main app — leave that empty so Xcode signs with just the default
  free-account entitlements.
- The files in `ios/ExpenseTrackerIntent/` are unused on this path; you
  can ignore them, or delete them if you want a cleaner project tree.

### Recommended Shortcut design (free account)

Same shape as the original Scriptable BankSMS shortcut, but the
per-iteration `Run Script` is replaced by `Import bank SMS batch`
(the App Intent):

```
1. Get Import Start Date         ← App Intent (returns N)
2. Adjust Date today − N days    → start
3. Repeat N times:
   3a. Adjust Date  start + (Repeat Index − 1)
   3b. Find Messages where Date is X
   3c. Repeat with Each:
        - Get Body
        - Combine Text  sender|||body
   3d. Combine Text  ===SMS===   (per-day text)
   3e. Import bank SMS batch  (combinedText = step 3d)   ← App Intent
```

iOS *will* show the **"Allow … to share with …"** prompt the first time.
Tap **Always Allow**. After that:

- It usually doesn't re-ask for the same shortcut as long as the
  parameter shape stays the same (a single `String`).
- You may see one re-prompt after iOS updates or after editing the
  shortcut, since iOS treats those as new privacy contexts.

### If the prompt keeps coming back even after "Always Allow"

This is a known iOS behavior with App Intents on free accounts —
unfortunately there's no code-side workaround that doesn't require
App Groups. Mitigations:

1. **Settings → Privacy & Security → Shortcuts** → set the shortcut to
   "Always Allow".
2. In the Shortcuts app, long-press the shortcut → **Details** →
   toggle off **Show When Run** and toggle off any "Confirm Before
   Sharing".
3. Make sure the parameter to `Import bank SMS batch` is a single
   **Combined Text** variable, not a list — iOS treats list-shaped
   payloads as a different signature each iteration.
4. Upgrade to a paid Developer account and follow Path B below to
   eliminate prompts entirely.

---

## Path B — Paid Developer account

This is the prompt-free path. Custom INIntents under the legacy
SiriKit trust model only get reviewed once per extension binary,
no matter how many times the shortcut calls in.

### Prerequisites

- Open `ios/ExpenseTracker.xcodeproj` in Xcode 15+.
- Sign in with the team that owns `com.rajesh.expensetracker.ios`.
- Apple Developer portal:
  - **Identifiers → App Groups → +** → name **Expense Tracker Group**, ID
    **`group.com.rajesh.expensetracker.ios`**.
  - On the existing app identifier (`com.rajesh.expensetracker.ios`),
    enable the **App Groups** capability and assign the group above.
- Regenerate the provisioning profile when prompted.

### 1. Add the Intents Extension target

1. **File → New → Target… → iOS → Intents Extension**.
2. Product Name: **ExpenseTrackerIntent** (must match the folder name).
3. Bundle identifier: **`com.rajesh.expensetracker.ios.intent`**.
4. Starting Point: **None / Custom intent** (we ship our own).
5. Embed in Application: **ExpenseTracker** (the main app).
6. Tap **Finish** — say **Activate** when prompted.

### 2. Replace the wizard's stubs with our files

The real ones are in `ios/ExpenseTrackerIntent/`. In Xcode:

1. Project Navigator → expand the new **ExpenseTrackerIntent** group.
2. **Delete** the stub `IntentHandler.swift` and `Info.plist`. Choose
   **Move to Trash** when prompted.
3. Right-click the **ExpenseTrackerIntent** group →
   **Add Files to "ExpenseTracker"…**
4. Pick the contents of `ios/ExpenseTrackerIntent/`:
   - `IntentHandler.swift`
   - `Info.plist`
   - `ExpenseTrackerIntent.entitlements`
5. **Targets**: tick only **ExpenseTrackerIntent**.

In the new target's build settings:
- **Code Signing Entitlements**: `ios/ExpenseTrackerIntent/ExpenseTrackerIntent.entitlements`
- **Info.plist File**: `ios/ExpenseTrackerIntent/Info.plist`
- **iOS Deployment Target**: 17.0
- **Swift Version**: 5.0

### 3. Wire the shared parsing files into the extension

Tick the extension target's membership in the File Inspector for each:

```
ExpenseTracker/Shared/AppGroup.swift           ✅ Main + Intent
ExpenseTracker/Shared/ImportCore.swift         ✅ Main + Intent
ExpenseTracker/BankSMSChunker.swift            ✅ Main + Intent
ExpenseTracker/SMSBankParser.swift             ✅ Main + Intent
ExpenseTracker/SMSMiniTemplates.swift          ✅ Main + Intent
ExpenseTracker/TransactionRecord.swift         ✅ Main + Intent
ExpenseTracker/Persistence.swift               ✅ Main + Intent
ExpenseTracker/ImportStartDateStore.swift      ✅ Main + Intent
ExpenseTracker/RulesStore.swift                ✅ Main + Intent
ExpenseTracker/ErrorLogStore.swift             ✅ Main + Intent
ExpenseTracker/CategoriesStore.swift           ✅ Main + Intent
ExpenseTrackerIntents.intentdefinition         ✅ Main + Intent
```

The `.intentdefinition` MUST be in **both** targets — Xcode's intent
codegen runs per target so each one gets its own
`ImportBankSMSCustomIntent`, `GetImportStartDaysCustomIntent`, and the
matching `*IntentHandling` protocols.

### 4. Link Intents.framework to the extension

Target **ExpenseTrackerIntent** → **General → Frameworks and Libraries
→ +** → **Intents.framework** (Status: **Required**). The main app
does not need this framework.

### 5. Enable App Groups on both targets

For **ExpenseTracker** AND **ExpenseTrackerIntent**:

- **Signing & Capabilities → + Capability → App Groups**.
- Tick **`group.com.rajesh.expensetracker.ios`**.

### 6. Set CODE_SIGN_ENTITLEMENTS on the main app

Project → **ExpenseTracker** target → Build Settings →
**Code Signing Entitlements** → `ExpenseTracker/ExpenseTracker.entitlements`.

(We left this **unset** in the shipped pbxproj so free-account users
can sign without errors. Set it manually after enabling App Groups.)

### 7. Build and verify

1. Build to a real device or simulator. Both targets should compile.
2. Open the **Shortcuts** app on the device.
3. Create a new shortcut. Search for **Import Bank SMS** — it appears
   under "Apps → Expense Tracker" (the extension provides it).
4. Pass any text into it — the response should say "✅ N imported".

### 8. Recommended Shortcut design (paid account)

Same shape, just call the **custom INIntent** instead of the App
Intent — and per-iteration calls now don't re-prompt:

```
1. Get Import Start Days         ← custom INIntent (returns N)
2. Adjust Date today − N days    → start
3. Repeat N times:
   3a. Adjust Date  start + (Repeat Index − 1)
   3b. Find Messages where Date is X
   3c. Repeat with Each:
        - Get Body
        - Combine Text  sender|||body
   3d. Combine Text  ===SMS===   (per-day text)
   3e. Import Bank SMS  (combinedText = step 3d)   ← custom INIntent
```

This is what Scriptable did all along — one call per day, never the
full window in memory. Custom INIntents under the legacy SiriKit
trust model only review once per extension binary, so the loop runs
silently after the first **Always Allow**.

### 9. Optional cleanup

Once the custom action works, you can delete the legacy App Intent
files (`Intents/ImportBankSMSIntent.swift`,
`Intents/GetImportStartDateIntent.swift`,
`Intents/ExpenseShortcuts.swift`). They were left in place so that
shortcuts wired to the App Intent don't break during the migration.
