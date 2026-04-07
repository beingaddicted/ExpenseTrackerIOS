# iOS Shortcut Setup — Bulk Export + Nightly Automation

## How It Works

1. A single **Bulk Export** Shortcut + **BankSMS.js** (Scriptable) exports all bank SMS to `exportSms.txt`
2. Set up a **nightly automation** to re-run the same shortcut every day — it picks up only new messages
3. Open the Expense Tracker PWA → tap 📂 → pick `exportSms.txt`
4. The app uses **delta import** — only new lines are parsed, old entries are skipped automatically
5. All data lives on your device in IndexedDB — nothing is sent anywhere

---

## Step 1 — Initial Bulk Export

1. Install **[Scriptable](https://apps.apple.com/app/scriptable/id1405459188)** from the App Store (free)
2. Create a new script in Scriptable named **BankSMS**, paste the contents of `data/ShortCuts/BankSMS.js`
3. Install the Bulk Export Shortcut: [Install Shortcut](https://www.icloud.com/shortcuts/eb49974416914b54995b1e0b34d28263)
4. Run it once — it processes every day from 2020 to today
5. Output: **Files → iCloud Drive → Scriptable → expense tracker → exportSms.txt**

> **Crash safe:** If the shortcut stops mid-run, just re-run — it resumes automatically. No duplicates.

---

## Step 2 — Nightly Automation (Set & Forget)

Re-use the same Bulk Export shortcut. Schedule it to run once a night:

1. **Shortcuts** → **Automation** tab → **＋** → **Time of Day**
2. Set time to **11:00 PM**, choose **Daily**, tap **Next**
3. Tap **Run Shortcut** → pick the **Bulk Export** shortcut
4. Turn **OFF** "Ask Before Running" → **Done**

The script adds +1 day overlap so nothing is ever missed. Cross-day duplicates are filtered by BankSMS.js.

---

## Step 3 — Import into the App

1. Open Expense Tracker in Safari (from Home Screen if added)
2. Tap the **📂** button in the header
3. Navigate to **iCloud Drive → Scriptable → expense tracker** → select **exportSms.txt**
4. App shows: "X added, Y duplicates, Z failed"
5. Done! The app remembers where it left off — re-importing the same file only parses new (delta) entries

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
