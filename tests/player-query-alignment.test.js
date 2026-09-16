const fs=require('fs');
const html=fs.readFileSync('public/index.html','utf8');
const forbidden=['nickname,position,best_position,jersey_number','passport_number','passport_frame','kyc_status,dna_technical','biography,passport_number','phone,clubs(name)'];
for(const token of forbidden){if(html.includes(token)) throw new Error('Legacy player query token remains: '+token);}
for(const token of ['preferred_name','football_passport_no','verification_status','dna_goalkeeper']){if(!html.includes(token)) throw new Error('Canonical player column missing: '+token);}
console.log('player query alignment guard: PASS');
