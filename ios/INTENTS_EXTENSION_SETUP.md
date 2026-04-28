# Adding the Intents Extension target

Apple's wizard does the boilerplate; we drop our pre-written files into it.
Skipping any step here will fail the build, so do them in order.

---

## 0. Prerequisites

- Open `ios/ExpenseTracker.xcodeproj` in Xcode 15+.
- Sign in with the team that owns `com.rajesh.expensetracker.ios`.
- In your Apple Developer portal:
  - **Identifiers → App Groups → +** → name **Expense Tracker Group**, ID
    **`group.com.rajesh.expensetracker.ios`**.
  - On the existing app identifier (`com.rajesh.expensetracker.ios`),
    enable the **App Groups** capability and assign the group above.
- Regenerate the provisioning profile when prompted.

---

## 1. Add the Intents Extension target

1. **File → New → Target… → iOS → Intents Extension**.
2. Product Name: **ExpenseTrackerIntent**
   (must match the folder name we already pre-populated).
3. Bundle identifier: **`com.rajesh.expensetracker.ios.intent`**.
4. Starting Point: **None / Custom intent** (we ship our own).
5. Embed in Application: **ExpenseTracker** (the main app).
6. Tap **Finish** — say **Activate** when prompted.

Xcode adds:
- A target with its own build configuration.
- An **Embed App Extensions** copy phase on the main app target.
- A stub `IntentHandler.swift` (we replace it).
- A stub `Info.plist` (we replace it).

---

## 2. Replace the wizard's files with ours

We already committed the real ones in `ios/ExpenseTrackerIntent/`. Tell
Xcode to use those files:

1. In the Project Navigator, expand the new **ExpenseTrackerIntent** group.
2. **Delete** `IntentHandler.swift` and `Info.plist` (the wizard's stubs).
   When prompted, choose **Move to Trash**.
3. Right-click the **ExpenseTrackerIntent** group → **Add Files to "ExpenseTracker"…**
4. Select the contents of `ios/ExpenseTrackerIntent/`:
   - `IntentHandler.swift`
   - `Info.plist`
   - `ExpenseTrackerIntent.entitlements`
5. **Targets**: tick only **ExpenseTrackerIntent**.
6. Build phase: **Copy items if needed** OFF (already in place).

In the new target's build settings:
- **Code Signing Entitlements**: `ios/ExpenseTrackerIntent/ExpenseTrackerIntent.entitlements`
- **Info.plist File**: `ios/ExpenseTrackerIntent/Info.plist`
- **iOS Deployment Target**: 17.0
- **Swift Version**: 5.0

---

## 3. Wire up the shared parsing files

The extension needs to compile the same parser code the main app uses.
Add these *existing* files to the **ExpenseTrackerIntent** target's
membership (Project Navigator → file → File Inspector → Target Membership):

```
ExpenseTracker/Shared/AppGroup.swift               ✅ Main + Intent
ExpenseTracker/Shared/ImportCore.swift             ✅ Main + Intent
ExpenseTracker/BankSMSChunker.swift                ✅ Main + Intent
ExpenseTracker/SMSBankParser.swift                 ✅ Main + Intent
ExpenseTracker/SMSMiniTemplates.swift              ✅ Main + Intent
ExpenseTracker/TransactionRecord.swift             ✅ Main + Intent
ExpenseTracker/Persistence.swift                   ✅ Main + Intent
ExpenseTracker/ImportStartDateStore.swift          ✅ Main + Intent
ExpenseTracker/RulesStore.swift                    ✅ Main + Intent
ExpenseTracker/ErrorLogStore.swift                 ✅ Main + Intent
ExpenseTracker/CategoriesStore.swift               ✅ Main + Intent
ExpenseTrackerIntents.intentdefinition             ✅ Main + Intent
```

The `.intentdefinition` MUST be in **both** targets — Xcode's intent
codegen runs per target so each one gets its own `ImportBankSMSCustomIntent`,
`GetImportStartDaysCustomIntent`, and the matching `*IntentHandling`
protocols.

---

## 4. Link `Intents.framework` to the extension

Target **ExpenseTrackerIntent** → **General → Frameworks and Libraries →
+** → **Intents.framework** (Status: **Required**).

The main app does **not** need this framework — only the extension does.

---

## 5. Enable App Groups on both targets

Both **ExpenseTracker** and **ExpenseTrackerIntent**:

- **Signing & Capabilities → + Capability → App Groups**.
- Tick **`group.com.rajesh.expensetracker.ios`** (created in step 0).

The matching `.entitlements` files are already on disk; the capability
panel just toggles the entry.

---

## 6. Build and verify

1. Select the main **ExpenseTracker** scheme → build to a real device or
   simulator. Both targets should compile.
2. Open the **Shortcuts** app on the device.
3. Create a new shortcut. Search for **Import Bank SMS** — it should
   appear under "Apps → Expense Tracker" (the extension provides it now).
4. Pass any text into it — the response should say "✅ N imported" or
   "⚠️ No bank transactions found" depending on payload.

If the action doesn't show up:

- Confirm the extension built (check the `.appex` bundle exists in the
  build products).
- Confirm the extension's `Info.plist` has `IntentsSupported` listing
  `ImportBankSMSCustomIntent` and `GetImportStartDaysCustomIntent`.

---

## 7. Update the iOS Shortcut definition

The shortcut shape mirrors the original Scriptable BankSMS one — call the
extension **once per day inside the outer Repeat**, NOT once at the very
end. That's both safer (no multi-year combined-text in RAM) and possible
again now (custom INIntents don't trigger the per-call privacy review).

Recommended actions, in order:

```
1. Get Import Start Days        ← custom INIntent (returns N)
2. Adjust Date  today − N days  → start
3. Repeat N times:
   3a. Adjust Date  start + (Repeat Index − 1)
   3b. Find Messages  where Date is X
   3c. Repeat with Each:
        - Get Body
        - Combine Text  sender|||body
   3d. Combine Text  ===SMS===  (per-day text)
   3e. Import Bank SMS  (combinedText = step 3d)   ← custom INIntent, per day
```

This is what Scriptable did all along — one call per day, never the full
window in memory.

Why this is now prompt-free:

- Custom INIntents (this extension) live under the legacy SiriKit trust
  model. iOS records **one** trust grant per extension binary, regardless
  of how many times the Shortcut calls in.
- App Intents (the previous design, in `ImportBankSMSIntent.swift` in
  the main app) are reviewed per call by the iOS 16+ Privacy framework
  even when the call site is identical.
- Both can co-exist on disk; new shortcuts should target **Import Bank SMS**
  (custom) rather than **Import bank SMS batch** (App Intent).

---

## 8. Optional: Remove the App Intent

Once the custom action works on your device, you can safely delete the
old App Intent files (`Intents/ImportBankSMSIntent.swift`,
`Intents/GetImportStartDateIntent.swift`, `Intents/ExpenseShortcuts.swift`).
We left them in place so users who already wired the App Intent into
their shortcut don't break — but new shortcut builds should target the
custom INIntent.
