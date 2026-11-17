import { subscribeMember, getMemberState, logout } from "/js/supabase/member-store.js?v=20261117-1";
import { supabase } from "/js/supabase/client.js?v=20261117-2";
const $ = id => document.getElementById(id);
const form = $("organizer-form");
const panels = [...document.querySelectorAll(".wizard-step")];
const titles = ["Jenis Organizer","Nama paparan","Hubungan & kawasan operasi","Semakan"];
const categories = ["Individu","Kelab","Akademi","Sekolah","Universiti","Syarikat","NGO","Persatuan","Jabatan / Agensi Kerajaan","Komuniti","Lain-lain"];
const selectedTypes = new Set();
let step = 0;
let member = null;
function renderTypes(){
  const host = $("types-options");
  host.replaceChildren();
  categories.forEach(label => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "club-multi-option" + (selectedTypes.has(label) ? " selected" : "");
    button.textContent = label;
    button.setAttribute("aria-pressed", String(selectedTypes.has(label)));
    button.addEventListener("click", () => {
      if (selectedTypes.has(label)) selectedTypes.delete(label); else selectedTypes.add(label);
      renderTypes(); updateTypeSummary();
    });
    host.append(button);
  });
}
function updateTypeSummary(){
  $("types-summary").textContent = selectedTypes.size ? [...selectedTypes].join(", ") : "Pilih jenis Organizer";
}
$("types-trigger").addEventListener("click", () => {
  const panel = $("types-panel");
  const opening = panel.classList.contains("hidden");
  panel.classList.toggle("hidden");
  $("types-trigger").setAttribute("aria-expanded", String(opening));
});
$("types-done").addEventListener("click", () => {
  $("types-panel").classList.add("hidden");
  $("types-trigger").setAttribute("aria-expanded", "false");
});
function selectedNameMode(){return form.querySelector('input[name="nameMode"]:checked')?.value || "account";}
function updateNameMode(){
  const commercial = selectedNameMode() === "commercial";
  $("commercial-fields").classList.toggle("hidden", !commercial);
  form.elements.commercialNameMs.required = commercial;
  $("account-name-choice").textContent = member?.displayName || "Nama akaun PlayPro";
}
form.querySelectorAll('input[name="nameMode"]').forEach(input => input.addEventListener("change", updateNameMode));
function showStep(){
  panels.forEach((panel,index)=>panel.classList.toggle("hidden",index!==step));
  $("step-kicker").textContent = "LANGKAH " + (step+1) + " DARIPADA 4";
  $("step-title").textContent = titles[step];
  $("step-count").textContent = (step+1) + " / 4";
  $("progress-fill").style.width = ((step+1)/4*100) + "%";
  $("prev-step").style.visibility = step===0 ? "hidden" : "visible";
  $("next-step").textContent = step===3 ? "Hantar pendaftaran" : "Seterusnya →";
  $("form-error").textContent = "";
  if(step===3) renderReview();
}
function validateStep(){
  const panel = panels[step];
  for(const field of panel.querySelectorAll("input,select,textarea")){
    if(field.type==="checkbox" || field.type==="radio" || field.disabled || field.closest(".hidden")) continue;
    if(field.required && !field.value.trim()){field.focus();return "Sila lengkapkan semua medan wajib.";}
  }
  if(step===0 && !selectedTypes.size) return "Pilih sekurang-kurangnya satu jenis Organizer.";
  if(step===1 && selectedNameMode()==="commercial" && !form.elements.commercialNameMs.value.trim()) return "Masukkan nama komersial dalam Bahasa Melayu.";
  if(step===2){
    const phone = form.elements.phone.value.replace(/[\s()-]/g,"");
    if(!/^\d{7,15}$/.test(phone)){form.elements.phone.focus();return "Masukkan nombor telefon yang sah tanpa kod negara.";}
    const email = form.elements.email.value.trim();
    if(email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)){form.elements.email.focus();return "Semak format alamat e-mel.";}
    const wa = form.elements.whatsapp.value.replace(/[\s()-]/g,"");
    if(wa && !/^\d{7,15}$/.test(wa)){form.elements.whatsapp.focus();return "Semak nombor WhatsApp atau kosongkan jika tidak digunakan.";}
  }
  return "";
}
function val(name){return form.elements[name]?.value?.trim() || "—";}
function addReview(label,value){
  const item=document.createElement("div");item.className="review-item";
  const title=document.createElement("span");title.textContent=label;
  const detail=document.createElement("strong");detail.textContent=value;
  item.append(title,detail);$("review-content").append(item);
}
function renderReview(){
  $("review-content").replaceChildren();
  const displayName = selectedNameMode()==="account" ? (member?.displayName||"Nama akaun PlayPro") : val("commercialNameMs");
  const fields=[
    ["Jenis Organizer",[...selectedTypes].join(", ")],
    ["Nama akaun PlayPro",member?.displayName||"Ahli PlayPro"],
    ["Nama paparan Organizer",displayName],
    ["Nama komersial (BM)",selectedNameMode()==="commercial"?val("commercialNameMs"):"Tidak digunakan"],
    ["Nama komersial (English)",selectedNameMode()==="commercial"?val("commercialNameEn"):"Tidak digunakan"],
    ["E-mel",val("email")],
    ["Telefon",val("phoneCode")+" "+val("phone")],
    ["WhatsApp",form.elements.whatsapp.value.trim()?val("whatsappCode")+" "+val("whatsapp"):"—"],
    ["Negeri operasi",val("state")],
    ["Bandar / Daerah",val("district")],
    ["Alamat asas operasi",val("baseAddress")]
  ];
  fields.forEach(([label,value])=>addReview(label,value));
}
$("prev-step").addEventListener("click",()=>{if(step>0){step--;showStep();}});
$("next-step").addEventListener("click",async()=>{
  if(form.dataset.saved==="true"){location.assign("/profile.html");return;}
  const error=validateStep();if(error){$("form-error").textContent=error;return;}if(step<3){step++;showStep();return;}
  if(!form.elements.confirm.checked){$("form-error").textContent="Sila sahkan maklumat Organizer.";return;}
  const button=$("next-step");button.disabled=true;button.textContent="Menyimpan...";const get=name=>form.elements[name]?.value?.trim()||"";
  const typeCodes={"Individu":"individual","Kelab":"club","Akademi":"academy","Sekolah":"school","Universiti":"university","Syarikat":"company","NGO":"ngo","Persatuan":"association","Jabatan / Agensi Kerajaan":"government","Komuniti":"community","Lain-lain":"other"};
  const payload={organizer_types:[...selectedTypes].map(x=>typeCodes[x]).filter(Boolean),name_mode:selectedNameMode(),commercial_name_ms:get("commercialNameMs"),commercial_name_en:get("commercialNameEn"),email:get("email"),phone_code:get("phoneCode"),phone:get("phone"),whatsapp_code:get("whatsappCode"),whatsapp:get("whatsapp"),state:get("state"),district:get("district"),base_address:get("baseAddress")};
  try{const saved=await supabase.rpc("save_my_organizer_onboarding",{p_payload:payload});if(saved.error)throw saved.error;if(!saved.data?.success)throw new Error("Profil Organizer tidak berjaya disimpan.");form.dataset.saved="true";$("form-error").textContent="Profil Organizer berjaya disimpan. Status pengesahan: "+(saved.data.verification_status||"pending")+". Keupayaan mengurus pertandingan hanya dibuka selepas pengesahan PlayPro.";button.disabled=false;button.textContent="Pergi ke Profil";}
  catch(err){button.disabled=false;button.textContent="Cuba semula";$("form-error").textContent=err?.message||"Profil Organizer gagal disimpan. Sila cuba semula.";}
});
$("logout").addEventListener("click",()=>logout("/"));
function applyMember(state){
  if(state.loading)return;
  if(!state.loggedIn){location.replace("/login.html?returnTo=%2Forganizer-onboarding.html");return;}
  member=state.member||null;
  const name=member?.displayName||"Nama akaun PlayPro";
  $("account-display-name").textContent=name;
  $("account-name-choice").textContent=name;
  updateNameMode();
}
subscribeMember(applyMember);
applyMember(getMemberState());
renderTypes();
showStep();