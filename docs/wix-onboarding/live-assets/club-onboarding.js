import { subscribeMember, getMemberState, logout } from "/js/supabase/member-store.js?v=20261117-1";
import { supabase } from "/js/supabase/client.js?v=20261117-2";
const $ = id => document.getElementById(id);
const form = $("club-form");
const panels = [...document.querySelectorAll(".wizard-step")];
const titles = ["Maklumat asas kelab","Alamat & lokasi kelab","Logo & semakan"];
const categories = ["Kelab Profesional","Kelab Separuh Profesional","Kelab Amatur","Akademi Bola Sepak / Akar Umbi","Institusi Pendidikan","Jabatan / Agensi Kerajaan","Kelab Korporat","Kelab Komuniti","Kelab Bola Sepak Wanita","Kelab Futsal","Kelab Pembangunan","Lain-lain"];
const selectedTypes = new Set();
let step = 0;
let member = null;
let logoObjectUrl = "";
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
      renderTypes();
      updateTypeSummary();
    });
    host.append(button);
  });
}
function updateTypeSummary(){
  const values = [...selectedTypes];
  $("types-summary").textContent = values.length ? values.join(", ") : "Pilih jenis kelab";
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
function showStep(){
  panels.forEach((panel,index)=>panel.classList.toggle("hidden",index!==step));
  $("step-kicker").textContent = "LANGKAH " + (step+1) + " DARIPADA 3";
  $("step-title").textContent = titles[step];
  $("step-count").textContent = (step+1) + " / 3";
  $("progress-fill").style.width = ((step+1)/3*100) + "%";
  $("prev-step").style.visibility = step===0 ? "hidden" : "visible";
  $("next-step").textContent = step===2 ? "Hantar pendaftaran" : "Seterusnya →";
  $("form-error").textContent = "";
  if(step===2) renderReview();
}
function validateStep(){
  const panel = panels[step];
  for(const field of panel.querySelectorAll("input,select,textarea")){
    if(field.type==="checkbox" || field.type==="file" || field.type==="url" || field.disabled || field.closest(".hidden")) continue;
    if(field.required && !field.value.trim()){field.focus();return "Sila lengkapkan semua medan wajib.";}
  }
  if(step===0 && !selectedTypes.size) return "Pilih sekurang-kurangnya satu jenis kelab.";
  if(step===1){
    const phone = form.elements.phone.value.replace(/[\s()-]/g,"");
    if(!/^\d{7,15}$/.test(phone)){form.elements.phone.focus();return "Masukkan nombor telefon yang sah tanpa kod negara. Pilih kod negara di ruangan sebelah.";}
    const url = form.elements.mapUrl.value.trim();
    if(url && !/^https?:\/\//i.test(url)){form.elements.mapUrl.focus();return "Pautan Google Maps mesti bermula dengan http:// atau https://.";}
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
  const mailing=[val("mailingAddress"),val("district"),val("state"),val("postcode")].join(", ");
  const fields=[
    ["Pemilik akaun",member?.displayName||"Ahli PlayPro"],
    ["Nama kelab",val("clubName")],
    ["Jenis kelab",[...selectedTypes].join(", ")||"—"],
    ["Tahun ditubuhkan",val("foundedYear")],
    ["No. pendaftaran ROS",val("registrationNumber")],
    ["Alamat Surat-Menyurat",mailing],
    ["Telefon",val("phoneCode")+" "+val("phone")],
    ["Padang latihan",val("groundName")],
    ["Alamat padang",val("groundAddress")],
    ["Pautan Google Maps",val("mapUrl")],
    ["Logo",logoObjectUrl?"Logo imej dipilih":$("ai-logo").dataset.selected==="true"?"Cadangan jana AI diminta":"Belum dipilih"]
  ];
  fields.forEach(([label,value])=>addReview(label,value));
}
$("map-search-btn").addEventListener("click",()=>{
  const query=$("map-search").value.trim() || $("ground-name").value.trim();
  if(!query){$("map-search").focus();$("form-error").textContent="Masukkan nama padang atau lokasi untuk dicari.";return;}
  const encoded=encodeURIComponent(query);
  $("map-frame").src="https://maps.google.com/maps?q="+encoded+"&output=embed";
  window.open("https://www.google.com/maps/search/?api=1&query="+encoded,"_blank","noopener");
  $("form-error").textContent="";
});
$("club-logo-file").addEventListener("change",event=>{
  const file=event.target.files?.[0];
  if(!file)return;
  if(!["image/png","image/jpeg","image/webp"].includes(file.type)){event.target.value="";$("form-error").textContent="Pilih fail PNG, JPG atau WebP.";return;}
  if(file.size>5*1024*1024){event.target.value="";$("form-error").textContent="Saiz logo maksimum ialah 5 MB.";return;}
  if(logoObjectUrl)URL.revokeObjectURL(logoObjectUrl);
  logoObjectUrl=URL.createObjectURL(file);
  $("logo-preview").src=logoObjectUrl;
  $("logo-status").textContent="Pratonton logo kelab";
  $("logo-detail").textContent=file.name;
  $("logo-preview-wrap").classList.remove("hidden");
  $("ai-logo").dataset.selected="false";
  $("form-error").textContent="";
});
$("ai-logo").addEventListener("click",()=>{
  $("ai-logo").dataset.selected="true";
  $("logo-note").textContent="Pilihan jana logo direkodkan dalam prototaip. Penjanaan imej AI sebenar akan disambungkan selepas servis dan aliran kelulusan logo ditetapkan.";
  $("logo-status").textContent="Permintaan logo AI dipilih";
  $("logo-detail").textContent="Penjanaan sebenar belum disambungkan.";
  $("logo-preview-wrap").classList.remove("hidden");
  $("logo-preview").removeAttribute("src");
  if(logoObjectUrl){URL.revokeObjectURL(logoObjectUrl);logoObjectUrl="";}
  $("club-logo-file").value="";
});
$("remove-logo").addEventListener("click",()=>{
  if(logoObjectUrl)URL.revokeObjectURL(logoObjectUrl);
  logoObjectUrl="";
  $("club-logo-file").value="";
  $("ai-logo").dataset.selected="false";
  $("logo-preview-wrap").classList.add("hidden");
});
$("prev-step").addEventListener("click",()=>{if(step>0){step--;showStep();}});
$("next-step").addEventListener("click",async()=>{
  if(form.dataset.saved==="true"){location.assign("/profile.html");return;}
  const error=validateStep();if(error){$("form-error").textContent=error;return;}if(step<2){step++;showStep();return;}
  if(!form.elements.confirm.checked){$("form-error").textContent="Sila sahkan maklumat kelab.";return;}
  const button=$("next-step");button.disabled=true;button.textContent="Menyimpan...";const get=name=>form.elements[name]?.value?.trim()||"";let uploadedPath=null;
  const categoryCodes={"Kelab Profesional":"professional","Kelab Separuh Profesional":"semi_professional","Kelab Amatur":"amateur","Akademi Bola Sepak / Akar Umbi":"grassroots_academy","Institusi Pendidikan":"educational_institution","Jabatan / Agensi Kerajaan":"government_agency","Kelab Korporat":"corporate","Kelab Komuniti":"community","Kelab Bola Sepak Wanita":"womens_club","Kelab Futsal":"futsal","Kelab Pembangunan":"development","Lain-lain":"other"};
  try{
    const file=$("club-logo-file").files?.[0];let logoUrl=null;
    if(file){if(file.size>5*1024*1024)throw new Error("Saiz logo maksimum ialah 5 MB.");const safeName=file.name.replace(/[^a-zA-Z0-9._-]/g,"_");uploadedPath=member.id+"/"+Date.now()+"-"+safeName;const upload=await supabase.storage.from("club-logos").upload(uploadedPath,file,{upsert:false,contentType:file.type});if(upload.error)throw upload.error;logoUrl=supabase.storage.from("club-logos").getPublicUrl(uploadedPath).data.publicUrl;}
    const payload={name:get("clubName"),club_categories:[...selectedTypes].map(x=>categoryCodes[x]).filter(Boolean),year_founded:get("foundedYear"),ros_registration_no:get("registrationNumber"),description:get("description"),mailing_address:get("mailingAddress"),state:get("state"),district:get("district"),postcode:get("postcode"),contact_phone:(get("phoneCode")+" "+get("phone")).trim(),country:"Malaysia",logo_url:logoUrl,ground_name:get("groundName"),ground_address:get("groundAddress"),map_url:get("mapUrl"),visibility:"public"};
    const saved=await supabase.rpc("save_my_club_onboarding",{p_payload:payload});if(saved.error)throw saved.error;if(!saved.data?.success)throw new Error("Rekod kelab tidak berjaya disimpan.");
    form.dataset.saved="true";$("form-error").textContent="Kelab berjaya didaftarkan dengan kod "+(saved.data.club_code||"PlayPro")+". Status pengiktirafan: "+(saved.data.verification_status||"pending")+".";
    if(!file&&$("ai-logo").dataset.selected==="true")$("form-error").textContent+=" Logo AI belum dijana; kelab disimpan tanpa logo.";button.disabled=false;button.textContent="Pergi ke Profil";
  }catch(err){if(uploadedPath)await supabase.storage.from("club-logos").remove([uploadedPath]);button.disabled=false;button.textContent="Cuba semula";$("form-error").textContent=err?.message||"Pendaftaran kelab gagal disimpan. Sila cuba semula.";}
});
$("logout").addEventListener("click",()=>logout("/"));
function applyMember(state){
  if(state.loading)return;
  if(!state.loggedIn){location.replace("/login.html?returnTo=%2Fclub-onboarding.html");return;}
  member=state.member||null;
  $("account-display-name").textContent=member?.displayName||"Nama akaun PlayPro";
}
subscribeMember(applyMember);
applyMember(getMemberState());
renderTypes();
showStep();

