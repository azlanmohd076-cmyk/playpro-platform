import { subscribeMember, getMemberState, logout } from "/js/supabase/member-store.js?v=20261117-1";
import { supabase } from "/js/supabase/client.js?v=20261117-2";
const $ = (id) => document.getElementById(id);
const form = $("player-form");
let step = 0;
let member = null;
const steps = [...document.querySelectorAll(".wizard-step")];
const titles = ["Maklumat diri","Maklumat bola sepak","Maklumat hubungan","Semakan akhir"];
function parseMyDate(value){if(!/^\d{4}-\d{2}-\d{2}$/.test(value||""))return null;const [year,month,day]=value.split("-").map(Number);const date=new Date(year,month-1,day);if(date.getFullYear()!==year||date.getMonth()!==month-1||date.getDate()!==day)return null;return date;}
function ageFromDob(value){const d=parseMyDate(value);if(!d)return "";const now=new Date();let age=now.getFullYear()-d.getFullYear();if(now.getMonth()<d.getMonth()||(now.getMonth()===d.getMonth()&&now.getDate()<d.getDate()))age--;return age>=0?age:"";}
function formatMyDate(value){const d=parseMyDate(value);return d?new Intl.DateTimeFormat("ms-MY",{day:"2-digit",month:"2-digit",year:"numeric"}).format(d):"—";}
function updateAge(){const age=ageFromDob($("dob").value);$("age").value=age===""?"":age;$("guardian-section").classList.toggle("hidden",age===""||age>=18);$("adult-note").classList.toggle("hidden",age!==""&&age<18);}
$("dob").addEventListener("change",updateAge);
$("player-status").addEventListener("change",()=>{$("club-field").classList.toggle("hidden",!["Bernaung di kelab","Akademi"].includes($("player-status").value));});
function showStep(){steps.forEach((el,i)=>el.classList.toggle("hidden",i!==step));$("step-kicker").textContent="LANGKAH "+(step+1)+" DARIPADA 4";$("step-title").textContent=titles[step];$("step-count").textContent=(step+1)+" / 4";$("progress-fill").style.width=((step+1)*25)+"%";$("prev-step").style.visibility=step===0?"hidden":"visible";$("next-step").textContent=step===3?"Sahkan maklumat":"Seterusnya →";$("form-error").textContent="";if(step===3)renderReview();}
function validateStep(){const panel=steps[step];const age=ageFromDob($("dob").value);for(const field of panel.querySelectorAll("input,select")){if(field.type==="checkbox"||field.disabled||field.closest(".hidden"))continue;if(field.required&&!field.value.trim()){field.focus();return "Sila lengkapkan semua medan wajib.";}if(field.type==="email"&&field.value&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(field.value)){field.focus();return "Sila masukkan alamat e-mel yang sah.";}if(field.type==="number"&&field.value&&((field.min!==""&&Number(field.value)<Number(field.min))||(field.max!==""&&Number(field.value)>Number(field.max)))){field.focus();return "Sila semak nilai yang dimasukkan.";}}
if(step===0&&(!age||!parseMyDate($("dob").value)))return "Pilih tarikh lahir yang sah melalui kalendar.";if(step===2&&age<18){for(const name of ["guardianName","guardianEmail","guardianPhone"]){const f=form.elements[name];if(!f.value.trim()){f.focus();return "Maklumat ibu bapa atau penjaga wajib untuk pemain bawah 18 tahun.";}}}if(step===2&&age<18&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.elements.guardianEmail.value))return "Sila masukkan e-mel penjaga yang sah.";return "";}
function value(name){return form.elements[name]?.value?.trim()||"—";}
function addReview(label,val){const item=document.createElement("div");item.className="review-item";const l=document.createElement("span");l.textContent=label;const v=document.createElement("strong");v.textContent=val;item.append(l,v);$("review-content").append(item);}
function renderReview(){$("review-content").replaceChildren();const fields=[["Nama akaun PlayPro",member?.displayName||"Ahli PlayPro"],["Tarikh lahir",formatMyDate(value("dob"))],["Umur",value("age")+" tahun"],["Jantina",value("gender")],["Negeri",value("state")],["Tinggi",value("height")+" cm"],["Berat",value("weight")+" kg"],["Posisi utama",value("position")],["Posisi tambahan",value("secondaryPosition")],["Kaki dominan",value("foot")],["Status pemain",value("playerStatus")],["Kelab / akademi",value("clubName")],["Pengalaman",value("experience")],["Telefon pemain",value("playerCode")+" "+value("playerPhone")]];if(Number(value("age"))<18)fields.push(["Nama penjaga",value("guardianName")],["E-mel penjaga",value("guardianEmail")],["Telefon penjaga",value("guardianCode")+" "+value("guardianPhone")]);fields.forEach(([a,b])=>addReview(a,b));}
$("prev-step").addEventListener("click",()=>{if(step>0){step--;showStep();}});
$("next-step").addEventListener("click",async()=>{
  if(form.dataset.saved==="true"){location.assign("/profile.html");return;}
  const error=validateStep();if(error){$("form-error").textContent=error;return;}
  if(step<3){step++;showStep();return;}
  if(!form.elements.confirm.checked){$("form-error").textContent="Sila sahkan maklumat anda.";return;}
  const button=$("next-step");button.disabled=true;button.textContent="Menyimpan...";
  const get=name=>form.elements[name]?.value?.trim()||"";
  const footMap={"Kanan":"right","Kiri":"left","Kedua-dua":"both"};
  const payload={date_of_birth:get("dob"),gender:get("gender"),state:get("state"),height_cm:get("height"),weight_kg:get("weight"),position:get("position"),secondary_position:get("secondaryPosition"),preferred_foot:footMap[get("foot")]||"",player_status:get("playerStatus"),club_name:get("clubName"),experience_level:get("experience"),phone_code:get("playerCode"),phone:get("playerPhone"),guardian_name:get("guardianName"),guardian_email:get("guardianEmail"),guardian_phone_code:get("guardianCode"),guardian_phone:get("guardianPhone")};
  try{
    const result=await supabase.rpc("register_my_player",{p_payload:payload});
    if(result.error)throw result.error;
    if(!result.data?.ok)throw new Error("Pelayan tidak mengesahkan penyimpanan profil pemain.");
    form.dataset.saved="true";$("form-error").textContent="Profil pemain berjaya disimpan. KYC pusat dan kelayakan pertandingan kekal mengikut status semakan PlayPro.";button.disabled=false;button.textContent="Pergi ke Profil";
  }catch(err){button.disabled=false;button.textContent="Cuba semula";$("form-error").textContent=err?.message||"Profil pemain gagal disimpan. Sila cuba semula.";}
});
$("logout").addEventListener("click",()=>logout("/"));
function applyMember(state){if(state.loading)return;if(!state.loggedIn){location.replace("/login.html?returnTo=%2Fplayer-onboarding.html");return;}member=state.member||null;$("account-display-name").textContent=member?.displayName||"Nama akaun PlayPro";}
subscribeMember(applyMember);
const initial=getMemberState();applyMember(initial);
showStep();
