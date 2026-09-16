const fs=require('fs');
const html=fs.readFileSync('public/index.html','utf8');
const forbidden=['nickname','pitch_nickname','preferred_jersey_no','dominant_foot','biography','passport_number','passport_frame','kyc_status','phone','city','is_free_agent'];
for(const token of forbidden){if(html.includes(token)) throw new Error('Legacy player query token remains: '+token);}
for(const token of ['preferred_name','football_passport_no','verification_status','dna_goalkeeper','position','best_position']){if(!html.includes(token)) throw new Error('Canonical player column missing: '+token);}
console.log('player query alignment guard: PASS');
