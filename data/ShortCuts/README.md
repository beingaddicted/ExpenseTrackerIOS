# iOS: Extract Bank SMS

---

## Quick Start — Bulk Export

The fastest way to get started:

1. Install **[Scriptable](https://apps.apple.com/app/scriptable/id1405459188)** from the App Store
2. Open Scriptable → **+** → paste `BankSMS.js` → rename to **BankSMS** → Done
3. **[Install the Shortcut](https://www.icloud.com/shortcuts/eb49974416914b54995b1e0b34d28263)** — tap the link on your iPhone → **Add Shortcut**
4. Run the shortcut from the Shortcuts app
5. When done, find the output at **Files → iCloud Drive → Scriptable → expense tracker → exportSms.txt**
6. Upload `exportSms.txt` into the Expense Tracker app via **Import** or **Batch Paste**

> **First run takes a while** — it processes every day since `DEFAULT_START` (2020-01-01). If it crashes, just re-run; it resumes from where it stopped.

To change start date, edit `DEFAULT_START` in the script (default: `2020-01-01`).

---

## Manual Setup (9-Action Shortcut)

If you prefer to build the Shortcut yourself instead of using the link above:

---

## The Shortcut (Step-by-Step)

Shortcuts → **+** → name: **Extract Bank SMS**

---

### 1 · Run Script _(from Scriptable)_

Search for **"Scriptable"** in the action list → pick **Run Script**

```
Script:  BankSMS
```

**Leave the text/parameter field empty.** Empty = init mode. The script detects this automatically.

Rename output → **total_days**

---

### 2 · Adjust Date

```
Date:     Current Date
Subtract: total_days  days
```

Rename output → **start_date**

---

### 3 · Repeat

```
Count: total_days
```

---

### 4 · Adjust Date _(inside Repeat)_

```
Date: start_date
Add:  Repeat Index  days
```

Rename output → **the_day**

---

### 5 · Find Messages _(inside Repeat)_

```
Filter: Date Received  is  the_day
Sort:   Date Received, Oldest First
```

No content filter. Gets ALL messages for that calendar day.

> **If "is" doesn't work as whole-day match:** use two filters instead:
> `Date Received is after the_day` and `Date Received is before the_day + 1 day`.

---

### 6 · Repeat with Each _(inside Repeat)_

```
Input: Find Messages result (from step 5)
```

---

### 7 · Text _(inside Repeat with Each)_

```
Content: {Sender of Repeat Item}|||{Repeat Item}
```

This extracts the **sender** (e.g. `HDFCBK`, `AXISBK`) and the **message body**, separated by `|||`. The script uses the sender to filter out non-bank messages.

---

### 8 · Combine Text _(inside Repeat, after End Repeat of step 6)_

```
Input:     Repeat Results (from step 6)
Separator: Custom → ===SMS===
```

The `===SMS===` delimiter keeps each SMS separate so the script can split them cleanly.

---

### 9 · Run Script _(inside Repeat, from Scriptable)_

```
Script:  BankSMS
```

Tap **Show More** → under **Texts** tap **+ Add** → tap the text field → insert the **Combined Text** variable from step 8.

---

**Done. No more actions needed.** Scriptable shows a notification when the last day is processed.

---

## What Each Action Does

```
┌───────────────────────────────────────────────────────────┐
│ SHORTCUT (9 actions)         SCRIPTABLE (BankSMS.js)      │
│                                                           │
│ 1. Scriptable "init"  ─────→ Read tracker                 │
│                        ←──── "2000"                       │
│                                                           │
│ 2. today − 2000 = start_date                              │
│                                                           │
│ 3. Repeat 2000×                                           │
│   4. start_date + index                                   │
│   5. Find Messages ← only Shortcuts can do this           │
│   6. Repeat with Each message:                            │
│      7. Text → extract sender|||body                      │
│   8. Combine Text (===SMS=== delimiter)                   │
│   9. Scriptable   ─────────→ Split on ===SMS===           │
│                               Parse sender|||body         │
│                               Filter known bank senders   │
│                               Filter 13 banking keywords  │
│                               Require money amount        │
│                               Extract time from SMS body  │
│                               Deduplicate                 │
│                               Append to exportSms.txt     │
│                               Update tracker              │
│                               Notify when done ✓          │
│                        ←──── "OK"                         │
│ End Repeat                                                │
└───────────────────────────────────────────────────────────┘
```

---

## Output

**Files → iCloud Drive → Scriptable → expense tracker → exportSms.txt**

```
2024-01-02 09:42 [HDFCBK] | INR Rs. 1500 debited from A/c no. 472912 on 02-01-24 09:42:37 at UPI/…
2024-01-05 [HDFCBK] | Sent Rs.450.00 From HDFC Bank A/C x7782 To AMAZON On 05/01/24 Ref 500512345678
2024-03-15 05:31 [ICICIB] | INR 25000.00 credited to A/c no. XX2912 on 15-03-24 at 05:31:37 IST. Info - NEFT/…
```

Lines include sender tag, time when extractable from the SMS body, date-only otherwise.

---

## Crash → Re-run → Resumes

```
Run 1:  processes 400 days → crashes
        tracker says "2025-02-04"

Run 2:  init reads "2025-02-04" → returns remaining days
        picks up from next day. no duplicates.
```

---

## Automate

```
Shortcuts → Automation → + → Time of Day → 11 PM daily
Action: Run Shortcut → Extract Bank SMS
Run Without Asking: ON
```

---

## Troubleshooting

| Problem                          | Fix                                                                                                 |
| -------------------------------- | --------------------------------------------------------------------------------------------------- |
| "is" date filter gives 0 results | Add an Adjust Date (+1 day → day_end), change Find Messages to: is after the_day, is before day_end |
| Crashes on a busy day            | Edit `exportSmstracker.txt` in Files → Scriptable → expense tracker to skip past that date          |
| Want more/fewer keywords         | Edit `KEYWORDS` array in BankSMS.js                                                                 |
| Start over                       | Delete all files in Files → Scriptable → expense tracker folder                                     |
