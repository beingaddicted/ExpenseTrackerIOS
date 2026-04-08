const d = require('./data/ShortCuts/expenses_1.json');
const S = require('./js/sms-templates');
const noMatch = d.transactions.filter(t => t.rawSMS && !S.tryMatch(t.rawSMS));
console.log('Total unmatched:', noMatch.length);

function analyzeBank(bankName, list) {
  const items = list.filter(t => t.bank === bankName);
  if (!items.length) return;
  console.log(`\n=== ${bankName}: ${items.length} ===`);
  
  const patterns = [
    ['UPI Mandate Sent', /UPI Mandate.*Sent/i],
    ['Mandate debit', /Mandate.*debit/i],
    ['Sent Rs', /Sent Rs/i],
    ['Loan NACH/INSTALLMENT', /Loan.*NACH|INSTALLMENT|installment/i],
    ['Debit INR/Rs', /Debit INR|Debit Rs/i],
    ['Credit Alert', /Credit Alert/i],
    ['Update deposit', /Update.*deposited/i],
    ['Received Rs', /Received Rs/i],
    ['debited from', /debited\s+from/i],
    ['debited.*A\/c', /debited.*A\/c|A\/c.*debited/i],
    ['Spent INR/Rs', /Spent INR|Spent Rs/i],
    ['Payment.*received', /Payment.*received/i],
    ['NACH-DR', /NACH.*DR/i],
    ['Auto.*debit', /Auto.*debit|auto-debit/i],
    ['Standing Instruction', /Standing Instruction/i],
    ['Statement', /Statement|statement/i],
    ['OTP', /OTP/i],
    ['promo/offer', /offer|promo|apply|click|download|congratulat/i],
  ];
  
  const classified = new Set();
  for (const [name, rx] of patterns) {
    const m = items.filter(t => rx.test(t.rawSMS) && !classified.has(t));
    if (m.length > 0) {
      console.log(`  ${name}: ${m.length}`);
      console.log(`    ${m[0].rawSMS.substring(0, 220)}`);
      if (m.length > 1) console.log(`    ${m[1].rawSMS.substring(0, 220)}`);
      m.forEach(t => classified.add(t));
    }
  }
  const unc = items.filter(t => !classified.has(t));
  if (unc.length > 0) {
    console.log(`  Other: ${unc.length}`);
    unc.slice(0, 5).forEach(t => console.log(`    ${t.rawSMS.substring(0, 220)}`));
  }
}

['HDFC Bank', 'Axis Bank', 'Citibank', 'ICICI Bank', 'Unknown Bank', 'DBS Bank', 'IndusInd Bank', 'Yes Bank'].forEach(b => analyzeBank(b, noMatch));
