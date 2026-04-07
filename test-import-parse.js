const SMSParser = require('./js/sms-parser');
const data = require('./data/exportSms.json');

let parsed = 0, failed = 0, debit = 0, credit = 0, unknownMerchant = 0;
const bankCounts = {};
const catCounts = {};
const failedSamples = [];

data.messages.forEach(msg => {
  const ts = msg.date && msg.time ? msg.date + ' ' + msg.time : msg.date;
  const txn = SMSParser.parse(msg.body, '', ts);
  if (txn) {
    parsed++;
    if (txn.type === 'debit') debit++;
    else credit++;
    if (txn.merchant === 'Unknown') unknownMerchant++;
    bankCounts[txn.bank] = (bankCounts[txn.bank] || 0) + 1;
    catCounts[txn.category] = (catCounts[txn.category] || 0) + 1;
  } else {
    failed++;
    if (failedSamples.length < 10) failedSamples.push(msg.body.substring(0, 120));
  }
});

console.log('=== IMPORT PARSE TEST ===');
console.log('Total messages:', data.messages.length);
console.log('Parsed:', parsed, '(' + (parsed / data.messages.length * 100).toFixed(1) + '%)');
console.log('Failed to parse:', failed);
console.log('Debit:', debit, '| Credit:', credit);
console.log('Unknown merchant:', unknownMerchant, '(' + (unknownMerchant / parsed * 100).toFixed(1) + '%)');

console.log('\nTop Banks:');
Object.entries(bankCounts).sort((a, b) => b[1] - a[1]).slice(0, 10).forEach(([b, c]) => console.log('  ' + c + ' - ' + b));

console.log('\nCategories:');
Object.entries(catCounts).sort((a, b) => b[1] - a[1]).forEach(([c, n]) => console.log('  ' + n + ' - ' + c));

console.log('\nSample failed messages:');
failedSamples.forEach((s, i) => console.log('  ' + (i + 1) + '. ' + s));

// Duplicate check
console.log('\n=== DUPLICATE CHECK ===');
const txns = [];
let dupes = 0;
data.messages.forEach(msg => {
  const ts = msg.date && msg.time ? msg.date + ' ' + msg.time : msg.date;
  const txn = SMSParser.parse(msg.body, '', ts);
  if (txn) {
    if (SMSParser.isDuplicate(txn, txns)) {
      dupes++;
    } else {
      txns.push(txn);
    }
  }
});
console.log('Unique transactions:', txns.length);
console.log('Duplicates:', dupes);
