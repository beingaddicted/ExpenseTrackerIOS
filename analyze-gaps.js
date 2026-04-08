const d = require('./data/ShortCuts/expenses_1.json');
const SMSTemplates = require('./js/sms-templates');

const total = d.transactions.length;
let matched = 0, unmatched = 0, noSms = 0;
const unmatchedList = [];

for (const t of d.transactions) {
  const sms = t.rawSMS || '';
  if (!sms) { noSms++; continue; }
  const r = SMSTemplates.tryMatch(sms);
  if (r) { matched++; }
  else { unmatched++; unmatchedList.push(t); }
}

console.log(`\nTotal: ${total}, Matched: ${matched}, Unmatched: ${unmatched}, No SMS: ${noSms}`);
console.log(`Coverage: ${(matched/(total-noSms)*100).toFixed(1)}%`);

const noTpl = unmatchedList;

function show(label, arr, max=3) {
  console.log(`\n=== ${label}: ${arr.length} ===`);
  arr.slice(0, max).forEach(t => console.log('[' + t.bank + '] ' + (t.rawSMS || '').substring(0, 250)));
}

// HDFC Sent (no pipe)
show('HDFC Sent no-pipe', noTpl.filter(t => /Sent Rs.*HDFC|HDFC.*Sent Rs/i.test(t.rawSMS || '')), 10);

// HDFC Credit Alert 
show('HDFC Credit Alert', noTpl.filter(t => /Credit Alert.*HDFC/i.test(t.rawSMS || '')));

// Axis INR debited (no pipe)
show('Axis debited no-pipe', noTpl.filter(t => /INR.*debited.*Axis Bank/i.test(t.rawSMS || '')));

// Axis Card Spent
show('Axis Card Spent', noTpl.filter(t => /Spent INR.*Axis Bank Card/i.test(t.rawSMS || '')));

// Axis Payment Received
show('Axis Payment Received', noTpl.filter(t => /Payment of INR.*received.*Axis/i.test(t.rawSMS || '')));

// AMEX spent
show('AMEX spent', noTpl.filter(t => /AMEX.*spent|spent.*AMEX/i.test(t.rawSMS || '')));

// AMEX statement
show('AMEX statement', noTpl.filter(t => /AMEX.*statement/i.test(t.rawSMS || '')));

// Citi spent
show('Citi spent', noTpl.filter(t => /Citi.*spent|spent.*Citi/i.test(t.rawSMS || '')));

// DBS fresh funds
show('DBS fresh funds/credited', noTpl.filter(t => /fresh funds|credited with Rs/i.test(t.rawSMS || '')));

// ICICI
show('ICICI debit/spent', noTpl.filter(t => /ICICI/i.test(t.rawSMS || '') && /debited|spent/i.test(t.rawSMS || '')));

// Canara 
show('Canara', noTpl.filter(t => /Canara|CANBNK/i.test(t.rawSMS || '')));

// IndusInd
show('IndusInd', noTpl.filter(t => /IndusInd/i.test(t.rawSMS || '')));

// Payment of Rs (Pine Labs / Apay)
show('Payment of Rs/INR', noTpl.filter(t => /Payment of.*(?:Rs|INR)/i.test(t.rawSMS || '')));

// Received Rs (HDFC)
show('HDFC Received no-pipe', noTpl.filter(t => /Received Rs.*HDFC/i.test(t.rawSMS || '')));

// ATM
show('ATM', noTpl.filter(t => /ATM|cash withdrawal/i.test(t.rawSMS || '')));

// Others (promo/spam/SIP etc)
const other = noTpl.filter(t => {
  const s = t.rawSMS || '';
  return !(/Sent Rs|Credit Alert|debited|Spent INR|AMEX|Citi|fresh funds|credited|ICICI|Canara|CANBNK|IndusInd|Payment of|Received Rs|ATM|cash withdrawal/i.test(s));
});
show('Other (no pattern match)', other, 15);
