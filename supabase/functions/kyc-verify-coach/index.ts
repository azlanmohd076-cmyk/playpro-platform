import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const enc = new TextEncoder()
function b64url(v: Uint8Array | string) { const b = typeof v === 'string' ? enc.encode(v) : v; let s=''; for (const x of b) s+=String.fromCharCode(x); return btoa(s).replaceAll('+','-').replaceAll('/','_').replace(/=+$/g,'') }
function pemBytes(pem:string){const s=pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,'');const b=atob(s);return Uint8Array.from(b,c=>c.charCodeAt(0))}
function b64std(b:Uint8Array){let s='';for(const x of b)s+=String.fromCharCode(x);return btoa(s)}
function norm(v:string){return String(v||'').normalize('NFKD').replace(/[\u0300-\u036f]/g,'').toUpperCase().replace(/[^A-Z0-9 ]/g,' ').replace(/\s+/g,' ').trim()}
function clean(v:string){return String(v||'').replace(/[^A-Za-zÀ-ÿ' -]/g,' ').replace(/\s+/g,' ').trim()}
function nameScore(expected:string, actual:string){const a=norm(expected).split(' ').filter(x=>x.length>1);const b=norm(actual);return a.length?Math.round(a.filter(x=>b.includes(x)).length/a.length*100):0}
function extractName(text:string){const lines=text.split(/\r?\n/).map(x=>clean(x)).filter(Boolean);const labels=/^(NAMA|NAME|NAMA PENUH|FULL NAME)\s*[:\-]?\s*/i;for(let i=0;i<lines.length;i++){const m=lines[i].match(labels);if(m&&clean(lines[i].slice(m[0].length)).length>=3)return clean(lines[i].slice(m[0].length));}return lines.filter(x=>x.length>=3&&!/MALAYSIA|MYKAD|MYKID|PASSPORT|IDENTITY|ADDRESS|ALAMAT|CITIZEN|WARGANEGARA/i.test(x)&&!/\d/.test(x)).sort((a,b)=>b.length-a.length)[0]||null}
function extractMyKad(text:string){const m=text.replace(/O/gi,'0').match(/\b(\d{6})[- ]?(\d{2})[- ]?(\d{4})\b/);return m?`${m[1]}-${m[2]}-${m[3]}`:null}
function detectType(text:string,fallback:string){const t=norm(text);if(t.includes('MYKID'))return'mykid';if(t.includes('MYKAD')&&extractMyKad(text))return'mykad';if(t.includes('PASSPORT'))return'passport';return fallback}
function extractDob(text:string){const m=text.match(/\b(\d{1,2})[\/-](\d{1,2})[\/-](\d{4})\b/);return m?`${m[3]}-${m[2].padStart(2,'0')}-${m[1].padStart(2,'0')}`:null}
async function googleToken(sa:Record<string,string>){const now=Math.floor(Date.now()/1000);const h=b64url(JSON.stringify({alg:'RS256',typ:'JWT'}));const p=b64url(JSON.stringify({iss:sa.client_email,scope:'https://www.googleapis.com/auth/cloud-platform',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600}));const key=await crypto.subtle.importKey('pkcs8',pemBytes(sa.private_key),{name:'RSASSA-PKCS1-v1_5',hash:'SHA-256'},false,['sign']);const sig=await crypto.subtle.sign('RSASSA-PKCS1-v1_5',key,enc.encode(`${h}.${p}`));const r=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion:`${h}.${p}.${b64url(new Uint8Array(sig))}`})});if(!r.ok)throw new Error(`Google OAuth token error ${r.status}`);const d=await r.json();if(!d.access_token)throw new Error('Google OAuth token missing');return d.access_token as string}
async function processDoc(token:string,project:string,location:string,processor:string,bytes:Uint8Array,mime:string){const url=`https://${location}-documentai.googleapis.com/v1/projects/${encodeURIComponent(project)}/locations/${encodeURIComponent(location)}/processors/${encodeURIComponent(processor)}:process`;const r=await fetch(url,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({rawDocument:{mimeType:mime,content:b64std(bytes)},imagelessMode:true,fieldMask:'text,entities,pages.pageNumber'})});if(!r.ok)throw new Error(`Document AI process error ${r.status}`);return await r.json()}
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:corsHeaders})
 const url=Deno.env.get('SUPABASE_URL')!;let kycId=''
 try{
  const jwt=(req.headers.get('Authorization')||'').replace(/^Bearer\s+/i,'');if(!jwt)throw new Error('Authentication required')
  const secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || (()=>{const x=Deno.env.get('SUPABASE_SECRET_KEYS');return x?JSON.parse(x).default:null})();if(!secret)throw new Error('Supabase server secret is not configured')
  const admin=createClient(url,secret);const {data:au,error:ae}=await admin.auth.getUser(jwt);if(ae||!au.user)throw new Error('Invalid session')
  const {data:account,error:pe}=await admin.from('profiles').select('is_active').eq('id',au.user.id).maybeSingle();if(pe)throw pe;if(!account||account.is_active!==true)throw new Error('ACCOUNT_DISABLED_OR_INACTIVE')
  const body=await req.json();kycId=String(body?.kyc_id||'');if(!kycId)throw new Error('kyc_id diperlukan')
  const {data:k,error:ke}=await admin.from('identity_verifications').select('id,profile_id,subject_type,id_type,legal_name_claimed,birth_state_code,document_storage_paths,status,provider_status,match_status').eq('id',kycId).eq('profile_id',au.user.id).eq('subject_type','individual').maybeSingle();if(ke)throw ke;if(!k)throw new Error('KYC identiti PlayPro tidak ditemui')
  if(k.status!=='pending')return new Response(JSON.stringify({ok:true,status:k.status,kyc_id:k.id}),{headers:{...corsHeaders,'Content-Type':'application/json'}});if(k.provider_status==='processed'&&k.match_status!=='provider_error')return new Response(JSON.stringify({ok:true,status:'pending',kyc_id:k.id,provider_status:k.provider_status,match_status:k.match_status,already_processed:true}),{headers:{...corsHeaders,'Content-Type':'application/json'}})
  const paths=Array.isArray(k.document_storage_paths)?k.document_storage_paths:[];if(!paths.length||paths.length>2||paths.some((p:unknown)=>typeof p!=='string'||!p.startsWith(`${au.user.id}/`)))throw new Error('Dokumen KYC tidak sah')
  const saText=Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON'),project=Deno.env.get('GOOGLE_DOCUMENT_AI_PROJECT_ID'),location=Deno.env.get('GOOGLE_DOCUMENT_AI_LOCATION')||'asia-southeast1',processor=Deno.env.get('GOOGLE_DOCUMENT_AI_PROCESSOR_ID');if(!saText||!project||!processor)throw new Error('Google Document AI belum dikonfigurasi sepenuhnya')
  const {data:identity,error:ie}=await admin.from('profiles').select('full_name,date_of_birth').eq('id',au.user.id).maybeSingle();if(ie)throw ie;if(!identity)throw new Error('Profil identiti PlayPro tidak ditemui')
  // Claim the pending request atomically so duplicate clicks cannot run OCR concurrently.
  const {data:claimed,error:claimError}=await admin.from('identity_verifications')
    .update({status:'processing',provider:'google_document_ai',provider_status:'processing',match_status:'not_processed',updated_at:new Date().toISOString()})
    .eq('id',k.id).eq('status','pending').select('id').maybeSingle();
  if(claimError)throw claimError;
  if(!claimed){
    const {data:latest,error:latestError}=await admin.from('identity_verifications').select('status').eq('id',k.id).maybeSingle();
    if(latestError)throw latestError;
    return new Response(JSON.stringify({ok:true,status:latest?.status||'unknown',kyc_id:k.id}),{headers:{...corsHeaders,'Content-Type':'application/json'}});
  }
  const token=await googleToken(JSON.parse(saText));let ocr='',detectedName:string|null=null,detectedDob:string|null=null,type=k.id_type,masked:string|null=null
  for(const path of paths){const {data:file,error:de}=await admin.storage.from('kyc-documents').download(path);if(de||!file)throw new Error('Dokumen KYC tidak boleh dibaca');const lower=path.toLowerCase();const mime=lower.endsWith('.pdf')?'application/pdf':lower.endsWith('.png')?'image/png':'image/jpeg';const r=await processDoc(token,project,location,processor,new Uint8Array(await file.arrayBuffer()),mime);const text=String(r?.document?.text||'');ocr+=`\n${text}`;detectedName=detectedName||extractName(text);detectedDob=detectedDob||extractDob(text);type=detectType(text,type);const id=extractMyKad(text);if(id)masked=`••••••-${id.slice(7,9)}-••••`}
  const score=nameScore(identity.full_name,detectedName||ocr);const dobMatch=detectedDob&&identity.date_of_birth?detectedDob===identity.date_of_birth:true;const matchStatus=detectedName&&score>=90&&dobMatch?'match':score>=50?'inconclusive':'mismatch'
  // Re-check account status after external OCR; disabled accounts cannot complete processing.
  const {data:stillActive,error:activeError}=await admin.from('profiles').select('is_active').eq('id',au.user.id).maybeSingle();
  if(activeError)throw activeError;
  if(!stillActive||stillActive.is_active!==true)throw new Error('ACCOUNT_DISABLED_OR_INACTIVE');
  const {error:saveError}=await admin.from('identity_verifications').update({status:'pending',provider:'google_document_ai',provider_status:'processed',extracted_legal_name:detectedName,extracted_birth_date:detectedDob,extracted_id_type:type,extracted_identifier_masked:masked,match_status:matchStatus,match_score:score,processed_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq('id',k.id).eq('status','processing');
  if(saveError)throw saveError;
  return new Response(JSON.stringify({ok:true,status:'pending',kyc_id:k.id,provider:'google_document_ai',provider_status:'processed',match_status:matchStatus,match_score:score,extracted_legal_name:detectedName,extracted_birth_date:detectedDob,extracted_id_type:type,extracted_identifier_masked:masked}),{headers:{...corsHeaders,'Content-Type':'application/json'}})
 }catch(e){console.error(e);if(kycId){try{const secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')||(()=>{const x=Deno.env.get('SUPABASE_SECRET_KEYS');return x?JSON.parse(x).default:null})();if(secret)await createClient(url,secret).from('identity_verifications').update({status:'pending',provider_status:'error',updated_at:new Date().toISOString()}).eq('id',kycId).eq('status','processing')}catch{}}return new Response(JSON.stringify({ok:false,error:e instanceof Error?e.message:'KYC processing failed'}),{status:400,headers:{...corsHeaders,'Content-Type':'application/json'}})}
})