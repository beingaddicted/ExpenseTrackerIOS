# Expense Tracker — Transaction Display & Calculation Logic

## Tab Behavior

| Transaction Type | Expenses Tab | Total Expense Tab | Income Tab | All Tab | Amount Counted In |
|---|---|---|---|---|---|
| Regular debit (food, shopping, transport, etc.) | ✅ Shown | ✅ Shown | — | ✅ Shown | Expenses + Total Expense |
| Excluded debit (Investment, Savings, EMI & Loans, Credit Card Payment) | — | ✅ Shown | — | ✅ Shown | Total Expense only |
| Invalid debit (statement, report, balance alert) | — | — | ✅ Shown (⊘ badge) | — | Not counted |
| Valid credit (salary, freelance, interest) | — | — | ✅ Shown | ✅ Shown | Income |
| Non-genuine credit (refund, cashback, reward) | — | — | — | ✅ Shown | Not counted as Income |
| Invalid credit (report, alert, promo) | — | — | ✅ Shown (⊘ badge) | — | Not counted |

## Category Classification

### Expense-Excluded Categories
These are real money-out transactions that are NOT consumption expenses. They appear in **Total Expense** (with amount summed) but NOT in the **Expenses** tab:
- `Investment` — SIP, mutual fund, stock purchases
- `Savings` — FD, RD, PPF, NPS, EPF deposits, auto-sweep
- `EMI & Loans` — EMI auto-debits, loan repayments
- `Credit Card Payment` — CC bill payments from bank account

### Non-Genuine Credits
These credits are excluded from **Income** calculation:
- `Refund` — purchase refunds, reversals
- `Cashback & Rewards` — cashback, rewards, bonuses

### Invalid Transactions
Non-transactional SMS (no real money movement). Marked with ⊘ badge. **Only visible in Income tab** for review. Never counted in any sum.
- OTP, promo offers, balance inquiry, mini-statement
- Bank statement alerts, account summary, spending reports
- SIP/MF confirmations without debit, portfolio/NAV updates
- EMI schedule reminders (no debit), credit score alerts
- Broker margin reports, standing balance notifications
- Card activation, app prompts

## Summary Card Calculations

| Card | Formula |
|---|---|
| **Expenses** (shown when Expenses tab active) | Sum of valid debits excluding Investment, Savings, EMI & Loans, Credit Card Payment |
| **Total Expense** (shown when Total Expense tab active) | Sum of ALL valid debits |
| **Income** | Sum of valid credits excluding Refund and Cashback & Rewards |
| **Net Balance** | Income − Total Expense |

## Key Rules
1. `invalid` transactions are **excluded from all calculations** (sums, charts, quick stats)
2. `invalid` transactions are **only visible in the Income tab** (for manual review/toggle)
3. Users can toggle any transaction's invalid status via the ⊘ button
4. AI classification sets `invalid: true` for non-transactional SMS automatically
