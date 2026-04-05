# iOS Shortcut Setup — Local SMS-to-File Automation

## How It Works

1. iOS Shortcut auto-saves every bank SMS → `bank_sms.json` in Files app
2. Open the Expense Tracker PWA → tap 📂 → pick `bank_sms.json`
3. App parses all SMS, deduplicates, and adds new transactions
4. All data lives in your phone's browser localStorage — nothing is sent anywhere

---

## Option A: JSON File (Recommended)

### Create the Automation:

1. **Shortcuts** app → **Automation** → **+** → **Create Personal Automation**
2. **Message** → **Sender Contains** → add bank IDs:
   `HDFCBK, ICICIB, SBIBNK, AXISBK, KOTAKB, PNBSMS, YESBK, INDUSBK, FEDBNK, IDFCFB`
3. Tap **Next**

### Add These Actions:

**Action 1 — Text**

```
{"message":"[Shortcut Input]","sender":"[Sender]","timestamp":"[Current Date]"}
```

(Use "Shortcut Input" magic variable for the message body)

**Action 2 — Get File**

```
Service: iCloud Drive
File Path: Shortcuts/bank_sms.json
Error If Not Found: OFF
```

**Action 3 — If [File] has any value**

**Action 3a — Get Text from [File]**

**Action 3b — Replace Text**

```
Find: ]}
Replace: ,[Text from Action 1]]}
```

**Action 3c — Save File**

```
Save [Replaced Text] to: Shortcuts/bank_sms.json
Ask Where: OFF | Overwrite: ON
```

**Otherwise (first SMS, file doesn't exist):**

**Action 3d — Text**

```
{"messages":[[Text from Action 1]]}
```

**Action 3e — Save File**

```
Save to: Shortcuts/bank_sms.json
Ask Where: OFF
```

**End If**

4. Turn **OFF** "Ask Before Running"
5. Tap **Done**

### Result:

File at `iCloud Drive/Shortcuts/bank_sms.json` contains:

```json
{
  "messages": [
    {
      "message": "Rs.499 debited from a/c **4521...",
      "sender": "HDFCBK",
      "timestamp": "2026-04-05"
    },
    {
      "message": "Your ICICI Bank Acct XX8834...",
      "sender": "ICICIB",
      "timestamp": "2026-04-05"
    }
  ]
}
```

---

## Option B: Simple Text File (Easier to Set Up)

### Create the Automation:

1. Same trigger as Option A (Message → Sender Contains → bank IDs)
2. **One action only:**

**Action: Append Text**

```
Text: [Shortcut Input]
File: Shortcuts/bank_sms.txt
Make New Line: ON
```

3. Turn OFF "Ask Before Running" → Done

### Result:

File at `iCloud Drive/Shortcuts/bank_sms.txt`:

```
Rs.499 debited from a/c **4521 on 01-04-26 to VPA swiggy@paytm(UPI ref no 409812345678). Avl bal Rs.24,500.50 -HDFC Bank
Your ICICI Bank Acct XX8834 has been debited with INR 1,200.00 on 01-Apr-26 for Amazon. Avl Bal INR 45,230.00
```

---

## Loading Into the App

1. Open Expense Tracker in Safari (from Home Screen if added)
2. Tap the **📂** button in the header
3. Navigate to **iCloud Drive → Shortcuts** → select **bank_sms.json** (or .txt)
4. App shows: "X added, Y duplicates, Z failed"
5. Done! You can load the same file repeatedly — duplicates are auto-skipped

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

- The file keeps growing — that's fine. The app only adds new (non-duplicate) entries.
- After loading, your transactions live in **localStorage** — clearing browser data will erase them.
- Use **Export** (Settings → Export) to back up as CSV or JSON anytime.
- Works fully offline after first open (if added to Home Screen).
