# iOS Shortcut Setup

Two shortcut flows live alongside each other:

- **iOS Native App** — uses the in-app App Intent to provide the start date and to ingest SMS. **No Scriptable, no file is ever written.**
- **PWA (web)** — keeps the existing Scriptable + file-based flow.

If you only use the iOS app, you only need the **Native App** flow.

---

## A. iOS Native App Flow (recommended for iOS)

This replaces the old Scriptable INIT step with an App Intent. Nothing is
written to disk — the iOS app itself remembers where the last sync left off.

### One-time setup

1. Install the **Expense Tracker** iOS app and complete onboarding.
2. On the **"Import From When?"** prompt, pick how far back to fetch (1 month,
   3 months, 6 months, 1 year, 3 years, all time, or a custom date).
3. Open Apple's **Shortcuts** app → **＋ New Shortcut** → name it
   **"Expense Tracker"** (or anything; match it in Settings → Shortcut Name).

### Shortcut actions (in order)

1. **Get Import Start Date** — App Intent provided by Expense Tracker.
   Returns an integer N = number of days to walk back (with +1 overlap).
2. **Repeat with Each** — set count to the result of step 1.
3. Inside the loop:
   1. **Adjust Date** — start = today − N days; this iteration uses
      `start + Repeat Index − 1`.
   2. **Find Messages** — filter to that date.
   3. **Combine Text** — separator `===SMS===`.
4. After the loop, **Combine Text** all the per-day combined strings with
   `===SMS===`.
5. **Import bank SMS batch** — App Intent provided by Expense Tracker.
   Pass the combined text; the app parses, deduplicates, applies your
   classification rules, and advances its internal "last completed" date.

> Both intents appear under "Apps → Expense Tracker" inside Shortcuts.
> Voice phrases: "Get Expense Tracker import start date", "Import bank SMS in Expense Tracker".

### Nightly automation

Same as before: **Automation → Time of Day → Run Shortcut → Expense Tracker**.
Turn off "Ask Before Running". Each run advances the start date to today, so
the next run only fetches new days.

### Re-prompting from a fresh date

In **Settings → Import → Reset Import Start Date** (or after **Delete All Data**),
the app forgets the start date and asks again on next launch. The next
shortcut run will pick up from the new date with no manual changes.

---

## B. PWA Flow (file-based, unchanged)

For users running the web app, the original Scriptable script still applies.

1. Install **[Scriptable](https://apps.apple.com/app/scriptable/id1405459188)**.
2. Create a new script in Scriptable named **BankSMS**, paste the contents of
   `data/ShortCuts/BankSMS.js`.
3. Install the Bulk Export Shortcut: [Install Shortcut](https://www.icloud.com/shortcuts/9f91949ca6244224ad56d0cd25419877).
4. Run it once — it processes every day from 2020 to today and writes
   `iCloud Drive → Scriptable → expense tracker → SmsExtracts.json`.
5. Open the PWA → tap **📂** → pick `SmsExtracts.json`.

The PWA uses delta-import — re-importing the same growing file only adds new
entries. The iOS native app does **not** read any such file; ignore this
section if you're only using the iOS app.

---

## Bank SMS Sender IDs

### Indian Banks

| Bank       | IDs            |
| ---------- | -------------- |
| HDFC       | HDFCBK, HDFCBN |
| ICICI      | ICICIB         |
| SBI        | SBIBNK, SBIPSG |
| Axis       | AXISBK         |
| Kotak      | KOTAKB         |
| PNB        | PNBSMS         |
| BoB        | BOBTXN         |
| Yes Bank   | YESBK          |
| IndusInd   | INDUSBK        |
| Federal    | FEDBNK         |
| IDFC First | IDFCFB         |
| Canara     | CANBNK         |
| RBL        | RBLBNK         |

### Payment Apps

| App        | IDs    |
| ---------- | ------ |
| Google Pay | GPAY   |
| PhonePe    | PHNEPE |
| Paytm      | PYTM1  |

---

## Tips

- iOS native flow keeps state in the app — clearing iOS app data prompts you
  again for an import start date on next launch.
- PWA flow keeps state in `SmsExtracts.json` (last completed day) and in
  `localStorage` / IndexedDB on the browser side.
- Use **Settings → Export Data** in either app to back up as CSV or JSON.
