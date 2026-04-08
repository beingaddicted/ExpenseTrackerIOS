const fs = require('fs');
const sms = JSON.parse(fs.readFileSync('data/exportSms.json', 'utf8')).messages;
const txns = JSON.parse(fs.readFileSync('data/expenses.json', 'utf8')).transactions;

const smsSet = new Set(sms.map(m => (m.originalSms || m.body || '').trim()));
const txnSmsSet = new Set(txns.map(t => (t.originalSms || t.rawSMS || '').trim()).filter(Boolean));

let inSmsNotTxn = 0;
const missingExamples = [];
for (const m of sms) {
  const body = (m.originalSms || m.body || '').trim();
  if (!txnSmsSet.has(body)) {
    inSmsNotTxn++;
    if (missingExamples.length < 10) missingExamples.push({ date: m.date, body: body.substring(0, 150) });
  }
}

let inTxnNotSms = 0;
const txnOnlyExamples = [];
for (const t of txns) {
  const body = (t.originalSms || t.rawSMS || '').trim();
  if (body && !smsSet.has(body)) {
    inTxnNotSms++;
    if (txnOnlyExamples.length < 5) txnOnlyExamples.push({ date: t.date, body: body.substring(0, 150) });
  }
}

const dupes = sms.length - smsSet.size;

// Date coverage
const smsDates = [...new Set(sms.map(m => m.date))].sort();
const txnDates = [...new Set(txns.map(t => t.date))].sort();

console.log('=== DATA VERIFICATION ===');
console.log('exportSms.json:', sms.length, 'messages');
console.log('expenses.json:', txns.length, 'transactions');
console.log('Difference:', sms.length - txns.length, '(SMS that became non-transactions)');
console.log('');
console.log('SMS date range:', smsDates[0], '→', smsDates[smsDates.length - 1]);
console.log('Txn date range:', txnDates[0], '→', txnDates[txnDates.length - 1]);
console.log('');
console.log('Duplicate SMS bodies in export:', dupes);
console.log('In SMS but NOT in expenses:', inSmsNotTxn);
console.log('In expenses but NOT in SMS:', inTxnNotSms);
console.log('');

if (missingExamples.length > 0) {
  console.log('--- SMS not in expenses (first 10) ---');
  missingExamples.forEach(m => console.log(' ', m.date, '|', m.body));
}

if (txnOnlyExamples.length > 0) {
  console.log('\n--- Expenses not in SMS (first 5) ---');
  txnOnlyExamples.forEach(m => console.log(' ', m.date, '|', m.body));
}

// Check parsing quality
const noAmount = txns.filter(t => !t.amount || t.amount <= 0).length;
const noDate = txns.filter(t => !t.date).length;
const noId = txns.filter(t => !t.id).length;
const ids = txns.map(t => t.id);
const dupeIds = ids.length - new Set(ids).size;
const templated = txns.filter(t => t._template).length;
const invalid = txns.filter(t => t.invalid).length;

console.log('\n=== PARSING QUALITY ===');
console.log('Templated:', templated, '/', txns.length, '(' + (templated / txns.length * 100).toFixed(1) + '%)');
console.log('Invalid (non-transaction):', invalid);
console.log('No amount:', noAmount);
console.log('No date:', noDate);
console.log('No ID:', noId);
console.log('Duplicate IDs:', dupeIds);

// Merchant stats
const merchants = {};
txns.forEach(t => { merchants[t.merchant] = (merchants[t.merchant] || 0) + 1; });
const unknown = merchants['Unknown'] || 0;
console.log('Unknown merchant:', unknown, '/', txns.length, '(' + (unknown / txns.length * 100).toFixed(1) + '%)');

// Category stats
const cats = {};
txns.forEach(t => { cats[t.category] = (cats[t.category] || 0) + 1; });
const topCats = Object.entries(cats).sort((a, b) => b[1] - a[1]).slice(0, 10);
console.log('\n=== TOP CATEGORIES ===');
topCats.forEach(([c, n]) => console.log(' ', c + ':', n));

// Bank breakdown
const banks = {};
txns.forEach(t => { banks[t.bank || 'Unknown'] = (banks[t.bank || 'Unknown'] || 0) + 1; });
const topBanks = Object.entries(banks).sort((a, b) => b[1] - a[1]);
console.log('\n=== BANK BREAKDOWN ===');
topBanks.forEach(([b, n]) => console.log(' ', b + ':', n));
