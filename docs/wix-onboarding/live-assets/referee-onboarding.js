import { subscribeMember, getMemberState, logout } from "/js/supabase/member-store.js?v=20261117-1";
import { supabase } from "/js/supabase/client.js?v=20261117-2";
const $ = (id) => document.getElementById(id);
const form = $("referee-form");
let member = null;
let step = 0;
const steps = [...document.querySelectorAll(".wizard-step")];
const titles = ["Maklumat Pengadil","Lesen & kelayakan","Pengalaman pengadilan","Semakan & pentauliahan"];
function parseDate(value){if(typeof value!=="string"||!value)return null;const parts=value.split("-").map(Number);if(parts.length!==3||parts.some(n=>!Number.isInteger(n)))return null;const [y,m,d]=parts;if(y<1900||m<1||m>12||d<1||d>31)return null;const date=new Date(y,m-1,d);return date.getFullYear()===y&&date.getMonth()===m-1&&date.getDate()===d?date:null;}
function ageFromDob(value){const d=parseDate(value);if(!d)return "";const now=new Date();let age=now.getFullYear()-d.getFullYear();if(now.getMonth()<d.getMonth()||(now.getMonth()===d.getMonth()&&now.getDate()<d.getDate()))age--;return age>=0?age:"";}
function formatDate(value){const d=parseDate(value);return d?new Intl.DateTimeFormat("ms-MY",{day:"2-digit",month:"2-digit",year:"numeric"}).format(d):"—";}
function updateRefereeAge(){$("referee-age").value=ageFromDob($("referee-dob").value);}
$("referee-dob").addEventListener("input",updateRefereeAge);$("referee-dob").addEventListener("change",updateRefereeAge);
function raw(name){return form.elements[name]?.value?.trim()||"";}
function val(name){return raw(name)||"—";}
const multiOptions = {
  issuers: ["FAM","AFC","FIFA","Persatuan Bolasepak Negeri","Badan / persatuan lain"],
  qualifications: ["Pengadil","Penolong Pengadil","Pegawai Keempat","Penolong Pengadil Tambahan (AAR)","Pengadil Futsal","Pengadil Bola Sepak Pantai","Video Match Official (VAR)","Penilai Pengadil","Instruktur Pengadil"],
  experiences: ["Belum pernah menjadi pengadil","Perlawanan persahabatan / latihan","Sekolah / akademi","Bola sepak akar umbi / komuniti","Kejohanan amatur / daerah","Pertandingan peringkat negeri","Pertandingan peringkat kebangsaan","Liga / pertandingan profesional","Pertandingan antarabangsa"]
};
const multiSelected = {issuers:[], qualifications:[], experiences:[]};
const multiPrompts = {issuers:"Pilih badan pengeluar",qualifications:"Pilih jenis kelayakan",experiences:"Pilih satu atau lebih pengalaman"};
function renderMulti(key){
  const host=$(key+"-options");host.replaceChildren();
  multiOptions[key].forEach(label=>{
    const item=document.createElement("button");item.type="button";
    item.className="ref-multi-option"+(multiSelected[key].includes(label)?" selected":"");
    item.textContent=label;item.setAttribute("aria-pressed",String(multiSelected[key].includes(label)));
    item.addEventListener("click",()=>{
      if(multiSelected[key].includes(label))multiSelected[key]=multiSelected[key].filter(x=>x!==label);
      else multiSelected[key].push(label);
      renderMulti(key);
    });
    host.append(item);
  });
  const summary=$(key+"-summary");
  summary.textContent=multiSelected[key].length?multiSelected[key].join(", "):multiPrompts[key];
}
function closeMulti(key){$(""+key+"-panel").hidden=true;$(key+"-trigger").setAttribute("aria-expanded","false");}
Object.keys(multiOptions).forEach(key=>{
  renderMulti(key);
  $(key+"-trigger").addEventListener("click",()=>{
    const panel=$(key+"-panel");const opening=panel.hidden;
    Object.keys(multiOptions).forEach(other=>closeMulti(other));
    panel.hidden=!opening;$(key+"-trigger").setAttribute("aria-expanded",String(opening));
  });
});
document.querySelectorAll("[data-close]").forEach(button=>button.addEventListener("click",()=>closeMulti(button.dataset.close)));
function selectedMatches(){return [...form.querySelectorAll('input[name="matchTypes"]:checked')].map(x=>x.value);}
function updateLicenceVisibility(){
  const hasLicence=$("license-status").value==="licensed";
  $("licensed-fields").hidden=!hasLicence;
  $("licensed-fields").querySelectorAll("input,select,button").forEach(el=>{el.disabled=!hasLicence;});
  if(!hasLicence){
    multiSelected.issuers=[];multiSelected.qualifications=[];
    ["licenseGrade","licenseNumber","expiry","license-file"].forEach(id=>{const el=$(id);if(el){if(el.type==="file")el.value="";else el.value="";}});
    renderMulti("issuers");renderMulti("qualifications");
  }
}
$("license-status").addEventListener("change",updateLicenceVisibility);
updateLicenceVisibility();
function addReview(label,value){const item=document.createElement("div");item.className="review-item";const title=document.createElement("span");title.textContent=label;const detail=document.createElement("strong");detail.textContent=value;item.append(title,detail);$("review-content").append(item);}
function renderReview(){
  $("review-content").replaceChildren();
  const hasLicence=$("license-status").value==="licensed";
  const file=hasLicence?($("license-file").files[0]?.name||"Tiada fail dipilih"):"—";
  const rows=[["Nama akaun PlayPro",member?.displayName||"Ahli PlayPro"],["Tarikh lahir",formatDate(val("dob"))],["Umur",val("age")+" tahun"],["Jantina",val("gender")],["Negeri / kawasan",val("state")],["Telefon",val("phoneCode")+" "+val("phone")],["Status lesen",hasLicence?"Mempunyai lesen":"Belum mempunyai lesen diiktiraf"]];
  if(hasLicence)rows.push(["Badan pengeluar",multiSelected.issuers.join(", ")||"—"],["Kategori kelayakan",multiSelected.qualifications.join(", ")||"—"],["Gred / tahap",val("licenseGrade")],["Nombor lesen",val("licenseNumber")],["Tamat lesen",formatDate(val("expiry"))],["Fail lesen",file]);
  rows.push(["Pengalaman",multiSelected.experiences.join(", ")||"—"],["Tempoh",val("years")+" tahun"],["Jenis perlawanan",selectedMatches().join(", ")||"—"]);
  rows.forEach(([a,b])=>addReview(a,b));
}
function showStep(){steps.forEach((el,i)=>el.classList.toggle("hidden",i!==step));$("step-kicker").textContent="LANGKAH "+(step+1)+" DARIPADA 4";$("step-title").textContent=titles[step];$("step-count").textContent=(step+1)+" / 4";$("progress-fill").style.width=((step+1)*25)+"%";$("prev-step").style.visibility=step===0?"hidden":"visible";$("next-step").textContent=step===3?"Sahkan maklumat":"Seterusnya →";$("form-error").textContent="";if(step===3)renderReview();}
function validate(){const panel=steps[step];for(const field of panel.querySelectorAll("input,select")){if(field.type==="checkbox"||field.type==="file"||field.readOnly||field.disabled||field.closest(".hidden"))continue;if(field.required&&!field.value.trim()){field.focus();return "Sila lengkapkan semua medan wajib.";}}
if(step===0&&!ageFromDob($("referee-dob").value))return "Pilih tarikh lahir yang sah melalui kalendar.";
if(step===1&&$("license-status").value==="licensed"&&(multiSelected.issuers.length===0||multiSelected.qualifications.length===0||!raw("licenseNumber")||!$("license-file").files.length))return "Pilih sekurang-kurangnya satu badan pengeluar dan kategori kelayakan, kemudian lengkapkan nombor lesen serta muat naik salinan lesen.";
if(step===2&&multiSelected.experiences.length===0)return "Pilih sekurang-kurangnya satu pengalaman pengadilan.";
if(step===2&&selectedMatches().length===0)return "Pilih sekurang-kurangnya satu jenis perlawanan.";
return "";}
$("prev-step").addEventListener("click",()=>{if(step>0){step--;showStep();}});
$("next-step").addEventListener("click",async()=>{
  if(form.dataset.saved==="true"){location.assign("/profile.html");return;}
  const error=validate();if(error){$("form-error").textContent=error;return;}
  if(step<3){step++;showStep();return;}
  if(!form.elements.confirm.checked){$("form-error").textContent="Sila sahkan maklumat anda.";return;}
  const button=$("next-step");button.disabled=true;button.textContent="Menyimpan...";let uploadedPath=null;
  try{
    const licensed=raw("licenseStatus")==="licensed";const file=licensed?$("license-file").files?.[0]:null;
    if(licensed&&!file)throw new Error("Fail lesen diperlukan untuk menghantar permohonan lesen.");if(file&&file.size>10*1024*1024)throw new Error("Saiz fail lesen maksimum ialah 10 MB.");
    const payload={date_of_birth:raw("dob"),gender:raw("gender"),state:raw("state"),phone_code:raw("phoneCode"),phone:raw("phone"),pitch_nickname:raw("pitchNickname"),license_status:licensed?"licensed":"none",license_grade:raw("licenseGrade"),license_issuers:multiSelected.issuers,qualification_types:multiSelected.qualifications,experience_types:multiSelected.experiences,match_types:selectedMatches(),years_experience:raw("years"),license_number:raw("licenseNumber")};
    if(file){const safeName=file.name.replace(/[^a-zA-Z0-9._-]/g,"_");uploadedPath=member.id+"/"+Date.now()+"-"+safeName;const upload=await supabase.storage.from("referee-licenses").upload(uploadedPath,file,{upsert:false,contentType:file.type||"application/octet-stream"});if(upload.error)throw upload.error;}
    const saved=await supabase.rpc("save_my_referee_onboarding",{p_payload:payload});if(saved.error)throw saved.error;if(!saved.data?.success)throw new Error("Profil Pengadil tidak berjaya disimpan.");
    if(file){const issuer=multiSelected.issuers[0];const issuingBody=["FAM","AFC","FIFA"].includes(issuer)?issuer:"other";const licenseType=multiSelected.qualifications.join(", ")+(raw("licenseGrade")?" — "+raw("licenseGrade"):"");const lic=await supabase.rpc("playpro_referee_submit_license",{p_referee_id:saved.data.referee_id,p_issuing_body:issuingBody,p_license_type:licenseType,p_license_number:raw("licenseNumber"),p_document_path:uploadedPath,p_issue_date:null,p_expiry_date:raw("expiry")||null});if(lic.error)throw lic.error;}
    form.dataset.saved="true";$("form-error").textContent=licensed?"Profil Pengadil disimpan. Dokumen lesen berjaya dihantar dan menunggu semakan.":"Profil Pengadil disimpan. Pentauliahan PlayPro dan kuasa pengadilan rasmi kekal melalui proses berasingan.";button.disabled=false;button.textContent="Pergi ke Profil";
  }catch(err){if(uploadedPath)await supabase.storage.from("referee-licenses").remove([uploadedPath]);button.disabled=false;button.textContent="Cuba semula";$("form-error").textContent=err?.message||"Profil Pengadil gagal disimpan. Sila cuba semula.";}
});
$("logout").addEventListener("click",()=>logout("/"));
function applyMember(state){if(state.loading)return;if(!state.loggedIn){location.replace("/login.html?returnTo=%2Freferee-onboarding.html");return;}member=state.member||null;$("account-display-name").textContent=member?.displayName||"Nama akaun PlayPro";}
subscribeMember(applyMember);applyMember(getMemberState());showStep();
