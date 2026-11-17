import { subscribeMember, getMemberState, logout } from "/js/supabase/member-store.js?v=20261117-1";
import { supabase } from "/js/supabase/client.js?v=20261117-2";
const $ = (id) => document.getElementById(id);
const form = $("coach-form");
let step = 0;
const steps = [...document.querySelectorAll(".wizard-step")];
const titles = ["Maklumat Coach", "Fokus kejurulatihan", "Pengalaman & kelayakan", "Semakan akhir"];
const roleOptions = ["Ketua Jurulatih","Penolong Jurulatih","Jurulatih Penjaga Gol","Jurulatih Kecergasan & Fizikal","Jurulatih Teknikal & Kemahiran","Jurulatih Taktikal","Jurulatih Pembangunan Belia","Jurulatih Bola Sepak Akar Umbi","Jurulatih Set-Piece","Penganalisis Prestasi & Perlawanan"];
const ageOptions = ["Bawah 8 tahun","Bawah 10 tahun","Bawah 12 tahun","Bawah 15 tahun","Bawah 17 tahun","Bawah 19 tahun","Bawah 21 tahun","Senior","Veteran"];
const levelOptions = ["Kelab amatur","Kelab profesional"];
const qualificationOptions = ["Belum mempunyai sijil","Lesen FAM","Lesen AFC","Lesen FIFA","Sijil kejurulatihan lain","Sedang mengikuti kursus","Lain-lain"];
const selected = { roles: [], ages: [], levels: [], quals: [] };
function parseMyDate(value){if(!/^\d{4}-\d{2}-\d{2}$/.test(value||""))return null;const [year,month,day]=value.split("-").map(Number);const date=new Date(year,month-1,day);if(date.getFullYear()!==year||date.getMonth()!==month-1||date.getDate()!==day)return null;return date;}
function ageFromDob(value){const d=parseMyDate(value);if(!d)return "";const now=new Date();let age=now.getFullYear()-d.getFullYear();if(now.getMonth()<d.getMonth()||(now.getMonth()===d.getMonth()&&now.getDate()<d.getDate()))age--;return age>=0?age:"";}
function formatMyDate(value){const d=parseMyDate(value);return d?new Intl.DateTimeFormat("ms-MY",{day:"2-digit",month:"2-digit",year:"numeric"}).format(d):"—";}
function updateAge(){$("coach-age").value=ageFromDob($("coach-dob").value);}
$("coach-dob").addEventListener("change",updateAge);
function renderOptions(key,items){const host=$(key+"-options");host.replaceChildren();items.forEach(label=>{const option=document.createElement("button");option.type="button";option.className="multi-option"+(selected[key].includes(label)?" is-selected":"");option.textContent=label;option.setAttribute("aria-pressed",String(selected[key].includes(label)));option.addEventListener("click",()=>{if(selected[key].includes(label))selected[key]=selected[key].filter(item=>item!==label);else if(key==="quals"&&label==="Belum mempunyai sijil")selected[key]=[label];else{if(key==="quals")selected[key]=selected[key].filter(item=>item!=="Belum mempunyai sijil");selected[key].push(label);}updatePicker(key);});host.append(option);});}
function updatePicker(key){const list=selected[key];const labels={roles:"jawatan",ages:"kumpulan umur",levels:"kategori",quals:"kelayakan"};const prompts={roles:"Pilih jawatan",ages:"Pilih kumpulan umur",levels:"Pilih kategori kelab",quals:"Pilih kelayakan"};$(key+"-summary").textContent=list.length?(list.length<=2?list.join(", "):list.slice(0,2).join(", ")+" +"+(list.length-2)+" lagi"):prompts[key];$(key+"-count").textContent=list.length?list.join(" · "):"Boleh pilih lebih daripada satu";$(key+"-selected").textContent="";const options={roles:roleOptions,ages:ageOptions,levels:levelOptions,quals:qualificationOptions};renderOptions(key,options[key]);}
function togglePanel(key){const panel=$(key+"-panel");const opening=panel.classList.contains("hidden");panel.classList.toggle("hidden");$(key+"-trigger").setAttribute("aria-expanded",String(opening));}
["roles","ages","levels","quals"].forEach(key=>{updatePicker(key);$(key+"-trigger").addEventListener("click",()=>togglePanel(key));$(key+"-done").addEventListener("click",()=>togglePanel(key));});
function showStep(){steps.forEach((el,i)=>el.classList.toggle("hidden",i!==step));$("step-kicker").textContent="LANGKAH "+(step+1)+" DARIPADA 4";$("step-title").textContent=titles[step];$("step-count").textContent=(step+1)+" / 4";$("progress-fill").style.width=((step+1)*25)+"%";$("prev-step").style.visibility=step===0?"hidden":"visible";$("next-step").textContent=step===3?"Sahkan maklumat":"Seterusnya →";$("form-error").textContent="";if(step===3)renderReview();}
function validateStep(){const panel=steps[step];for(const field of panel.querySelectorAll("input,select")){if(field.type==="checkbox"||field.readOnly||field.disabled||field.closest(".hidden"))continue;if(field.required&&!field.value.trim()){field.focus();return "Sila lengkapkan semua medan wajib."; }if(field.type==="number"&&field.value&&((field.min!==""&&Number(field.value)<Number(field.min))||(field.max!==""&&Number(field.value)>Number(field.max)))){field.focus();return "Sila semak nilai yang dimasukkan.";}}if(step===0&&!ageFromDob($("coach-dob").value))return "Pilih tarikh lahir yang sah melalui kalendar.";if(step===0&&selected.roles.length===0)return "Pilih sekurang-kurangnya satu jawatan kejurulatihan.";if(step===1&&selected.ages.length===0)return "Pilih sekurang-kurangnya satu kumpulan umur.";if(step===1&&selected.levels.length===0)return "Pilih sekurang-kurangnya satu kategori kelab.";if(step===2&&selected.quals.length===0)return "Pilih sekurang-kurangnya satu kelayakan atau sijil.";return "";}
function val(name){return form.elements[name]?.value?.trim()||"—";}
function addReview(label,value){const item=document.createElement("div");item.className="review-item";const title=document.createElement("span");title.textContent=label;const detail=document.createElement("strong");detail.textContent=value;item.append(title,detail);$("review-content").append(item);}
function renderReview(){$("review-content").replaceChildren();const fields=[["Nama akaun PlayPro",member?.displayName||"Ahli PlayPro"],["Tarikh lahir",formatMyDate(val("dob"))],["Umur",val("age")+" tahun"],["Jantina",val("gender")],["Tinggi",val("height")+" cm"],["Berat",val("weight")+" kg"],["Negeri / kawasan",val("state")],["Jawatan kejurulatihan",selected.roles.join(", ")],["Kumpulan umur",selected.ages.join(", ")],["Kategori kelab",selected.levels.join(", ")],["Pengalaman",val("experience")],["Tempoh pengalaman",val("years")+" tahun"],["Kelayakan / sijil",selected.quals.join(", ")||"—"],["Sijil tambahan",val("otherCertificate")]];fields.forEach(([label,value])=>addReview(label,value));}
$("prev-step").addEventListener("click",()=>{if(step>0){step--;showStep();}});
$("next-step").addEventListener("click",async()=>{
  if(form.dataset.saved==="true"){location.assign("/profile.html");return;}
  const error=validateStep();if(error){$("form-error").textContent=error;return;}
  if(step<3){step++;showStep();return;}
  if(!form.elements.confirm.checked){$("form-error").textContent="Sila sahkan maklumat anda.";return;}
  const button=$("next-step");button.disabled=true;button.textContent="Menyimpan...";
  const get=name=>form.elements[name]?.value?.trim()||"";
  const roleCodes={"Ketua Jurulatih":"head_coach","Penolong Jurulatih":"assistant_coach","Jurulatih Penjaga Gol":"goalkeeper_coach","Jurulatih Kecergasan & Fizikal":"fitness_coach","Jurulatih Teknikal & Kemahiran":"technical_coach","Jurulatih Taktikal":"tactical_coach","Jurulatih Pembangunan Belia":"youth_development_coach","Jurulatih Bola Sepak Akar Umbi":"grassroots_coach","Jurulatih Set-Piece":"set_piece_coach","Penganalisis Prestasi & Perlawanan":"performance_analyst"};
  const payload={full_name:member?.displayName||"",date_of_birth:get("dob"),gender:get("gender"),height_cm:get("height"),weight_kg:get("weight"),state:get("state"),experience_level:get("experience"),years_experience:get("years"),coaching_roles:selected.roles,coaching_role:roleCodes[selected.roles[0]]||"head_coach",age_groups:selected.ages,club_categories:selected.levels,qualification_types:selected.quals,license_type:selected.quals.find(x=>x!=="Belum mempunyai sijil")||null,other_certificate:get("otherCertificate")};
  try{
    const result=await supabase.rpc("save_coach_onboarding_profile",{p_profile_id:member.id,p_payload:payload});
    if(result.error)throw result.error;if(!result.data?.success)throw new Error(result.data?.message||"Profil Coach tidak berjaya disimpan.");
    form.dataset.saved="true";$("form-error").textContent="Profil Coach berjaya disimpan. Status pengesahan Coach dan KYC kekal berasingan; fungsi yang memerlukan pengesahan belum dibuka.";button.disabled=false;button.textContent="Pergi ke Profil";
  }catch(err){button.disabled=false;button.textContent="Cuba semula";$("form-error").textContent=err?.message||"Profil Coach gagal disimpan. Sila cuba semula.";}
});
$("logout").addEventListener("click",()=>logout("/"));
function applyMember(state){if(state.loading)return;if(!state.loggedIn){location.replace("/login.html?returnTo=%2Fcoach-onboarding.html");return;}member=state.member||null;$("account-display-name").textContent=member?.displayName||"Nama akaun PlayPro";}
let member=null;
subscribeMember(applyMember);
const initial=getMemberState();applyMember(initial);
showStep();
