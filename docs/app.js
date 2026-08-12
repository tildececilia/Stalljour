"use strict";
/* ============ Uppkoppling ============ */
const cfg = window.STALLJOUR_CONFIG;
const db = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_KEY);

let session = null;            // {id, email} från Supabase Auth
let view = { name: "home", stableId: null };
let didAutoRoute = false;       // hoppa direkt till schemat om man bara har ett stall
let loginStage = "email";      // "email" | "code"
let loginEmail = "";

const GROUP_GREENS = ["#7bc088","#4e9e6e","#2b6242","#93d3a0","#3f8f5f","#1f4d36"];
let curAdmin = false;   // är jag admin i stallet som visas
let curCats = [];       // kategorier i stallet som visas (för pass-formuläret)
let curGroups = [];     // grupper i stallet (för häst-grupp-valet)
let editingPassId = null, editingHorseId = null, editingGroupId = null, editingCatId = null, editingProfileId = null;

/* ---- Datum & rotation ---- */
const MONTHS = ["jan","feb","mar","apr","maj","jun","jul","aug","sep","okt","nov","dec"];
const DAY_NAMES = ["Söndag","Måndag","Tisdag","Onsdag","Torsdag","Fredag","Lördag"];
const SHORT_DAYS = ["Sön","Mån","Tis","Ons","Tor","Fre","Lör"];
const ROT_ANCHOR = new Date(2024,0,1); // en måndag – referens för rotationen
function isoDate(d){ const p=n=>String(n).padStart(2,"0"); return d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate()); }
function startOfWeek(d){ const x=new Date(d); const day=(x.getDay()+6)%7; x.setDate(x.getDate()-day); x.setHours(0,0,0,0); return x; }
function isoWeekNumber(d){
  const t=new Date(Date.UTC(d.getFullYear(),d.getMonth(),d.getDate()));
  const day=(t.getUTCDay()+6)%7; t.setUTCDate(t.getUTCDate()-day+3);
  const f=new Date(Date.UTC(t.getUTCFullYear(),0,4)); const fd=(f.getUTCDay()+6)%7; f.setUTCDate(f.getUTCDate()-fd+3);
  return 1+Math.round((t-f)/(7*24*3600*1000));
}
function weekIndexOf(monday){ const a=new Date(ROT_ANCHOR); a.setHours(0,0,0,0); const m=new Date(monday); m.setHours(0,0,0,0); return Math.round((m-a)/(7*24*3600*1000)); }
function dutyGroupForWeek(monday, groups, offset){ const n=groups.length; if(!n) return null; const idx=((weekIndexOf(monday)+(offset||0))%n+n)%n; return groups[idx]; }
function passApplies(p, d){ const g=d.getDay(); const wknd=(g===0||g===6);
  if(p.day_rule==="weekend") return wknd;
  if(p.day_rule==="weekday") return !wknd;
  if(p.day_rule==="weekdays") return Array.isArray(p.weekdays) && p.weekdays.includes(((g+6)%7)+1);
  return true;
}
function timeKey(p){ const m=(p.start_time||"").trim().match(/^(\d{1,2}):(\d{2})/); return m ? (+m[1])*60 + (+m[2]) : 9999; }
function sortPassesByTime(arr){ return arr.slice().sort((a,b)=>{ const d=timeKey(a)-timeKey(b); return d!==0 ? d : ((a.sort_order||0)-(b.sort_order||0)); }); }
const TIME_OPTIONS = (()=>{ const a=[]; for(let h=0;h<24;h++) for(const m of [0,30]) a.push(String(h).padStart(2,"0")+":"+String(m).padStart(2,"0")); return a; })();
function capOpts(sel){ let o=""; for(let i=1;i<=10;i++) o += `<option value="${i}"${i===sel?" selected":""}>${i}</option>`; return o; }
let weekStart2 = null;   // schemats vecka (måndag)
let schedCtx = null;     // {stable, groups, passes, myProfiles, actingProfileId}

const appEl = document.getElementById("app");

/* ============ Hjälpare ============ */
function normEmail(e){ return (e||"").trim().toLowerCase(); }
function esc(s){ return String(s??"").replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c])); }
function el(id){ return document.getElementById(id); }
function msg(text, kind){ return `<div class="msg ${kind||""}">${esc(text)}</div>`; }
/* Konturikoner (Lucide-stil: streckade, ej ifyllda) */
const ICONS = {
  calendar: '<rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>',
  settings: '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
  user: '<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  moon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2"/><path d="M12 20v2"/><path d="m4.93 4.93 1.41 1.41"/><path d="m17.66 17.66 1.41 1.41"/><path d="M2 12h2"/><path d="M20 12h2"/><path d="m6.34 17.66-1.41 1.41"/><path d="m19.07 4.93-1.41 1.41"/>',
  home: '<path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>',
  plus: '<path d="M5 12h14"/><path d="M12 5v14"/>',
  logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>',
  clock: '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>',
  tag: '<path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42z"/><circle cx="7.5" cy="7.5" r="1"/>',
  mail: '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>',
  pencil: '<path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/>',
  x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>'
};
function ic(name){
  return `<svg class="icn" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name]||""}</svg>`;
}

/* ============ Router ============ */
function render(){
  updateHeader();
  if(!session){ didAutoRoute = false; renderLogin(); return; }
  if(view.name === "schedule" && view.stableId){ renderSchedule(view.stableId); return; }
  if(view.name === "stable" && view.stableId){ renderStable(view.stableId); return; }
  renderHome();
}

/* ============ Inloggning (mejl-länk) ============ */
function renderLogin(){
  appEl.innerHTML = `
    <div class="center">
      <div class="card">
        <h1 class="title">Välkommen!</h1>
        <p class="sub">Logga in med din mejl. Vi skickar en länk — inget lösenord behövs.</p>
        <div id="loginMsg"></div>
        <div class="field">
          <label class="fld" for="email">Mejladress</label>
          <input type="email" id="email" placeholder="du@exempel.se" autocomplete="email">
        </div>
        <button class="btn primary block" id="loginBtn">Skicka inloggningslänk</button>
        <div class="hint">Klicka på länken i mejlet så loggas du in. Du förblir inloggad på den här enheten.</div>
      </div>
    </div>`;
  el("loginBtn").onclick = doLogin;
  el("email").addEventListener("keydown", e=>{ if(e.key==="Enter") doLogin(); });
  el("email").focus();
}

async function doLogin(){
  const mEl = el("loginMsg"), btn = el("loginBtn");
  const email = normEmail(el("email").value);
  if(!email.includes("@") || email.length < 5){ mEl.innerHTML = msg("Skriv en giltig mejladress.", "err"); return; }
  btn.classList.add("spin"); btn.textContent = "…";
  const redirect = window.location.origin + window.location.pathname;
  const { error } = await db.auth.signInWithOtp({ email, options: { shouldCreateUser: true, emailRedirectTo: redirect } });
  btn.classList.remove("spin"); btn.textContent = "Skicka inloggningslänk";
  if(error){ mEl.innerHTML = msg("Kunde inte skicka: " + error.message, "err"); return; }
  mEl.innerHTML = msg("Vi skickade en inloggningslänk till " + email + ". Öppna mejlet och klicka på länken.", "ok");
}


/* ============ Hem – dina stall ============ */
async function renderHome(){
  appEl.innerHTML = `
    <div class="card">
      <h1 class="title">Hej!</h1>
      <p class="sub" style="margin:0 0 14px">Inloggad som ${esc(session.email)}</p>
      <p class="sub">Dina stall</p>
      <div id="stableList" class="list"><div class="empty">Laddar…</div></div>
    </div>
    <div class="card">
      <p class="sub" style="margin:0 0 12px">Starta ett nytt stall — du blir admin och kan lägga till profiler.</p>
      <div class="field"><input type="text" id="newStable" placeholder="Stallets namn, t.ex. RHC"></div>
      <button class="btn primary block" id="createStableBtn">Skapa nytt stall</button>
      <div id="homeMsg" style="margin-top:12px"></div>
    </div>`;
  el("createStableBtn").onclick = createStable;

  try{
    const stables = await loadMyStables();
    // Har man bara ett stall – gå direkt till schemat (en gång per inloggning)
    if(stables.length === 1 && !didAutoRoute){
      didAutoRoute = true;
      weekStart2 = startOfWeek(new Date());
      view = { name: "schedule", stableId: stables[0].id };
      render();
      return;
    }
    const list = el("stableList");
    if(!stables.length){ list.innerHTML = `<div class="empty">Du är inte med i något stall än. Skapa ett nedan, eller be en admin lägga in din mejl på en profil.</div>`; return; }
    list.innerHTML = stables.map(s=>`
      <button class="row" data-open="${s.id}">
        <div class="grow"><div class="nm">${esc(s.name)}</div><div class="meta">${s.isAdmin?"Admin":"Medlem"}</div></div>
        <span class="chev">›</span>
      </button>`).join("");
    list.querySelectorAll("[data-open]").forEach(b=> b.onclick = ()=>{ view={name:"stable",stableId:b.getAttribute("data-open")}; render(); });
  }catch(e){
    el("stableList").innerHTML = msg("Kunde inte hämta stall: " + (e.message||e), "err");
  }
}

async function loadMyStables(){
  const map = new Map();
  // stall där jag är admin
  const admin = await db.from("stable_admin").select("stable(*)").eq("email", session.email);
  if(admin.error) throw admin.error;
  admin.data.forEach(r=>{ if(r.stable) map.set(r.stable.id, { ...r.stable, isAdmin:true }); });
  // stall där jag är med via en profil
  const mem = await db.from("profile_member").select("profile(stable(*))").eq("email", session.email);
  if(mem.error) throw mem.error;
  mem.data.forEach(r=>{ const s=r.profile && r.profile.stable; if(s && !map.has(s.id)) map.set(s.id, { ...s, isAdmin:false }); });
  return [...map.values()];
}

async function createStable(){
  const name = el("newStable").value.trim();
  const mEl = el("homeMsg");
  if(!name){ mEl.innerHTML = msg("Ge stallet ett namn.", "err"); return; }
  const btn = el("createStableBtn"); btn.classList.add("spin"); btn.textContent="…";
  try{
    const { data, error } = await db.rpc("create_stable", { p_name: name });
    if(error) throw error;
    view = { name:"stable", stableId: data };
    render();
  }catch(e){
    mEl.innerHTML = msg("Kunde inte skapa stall: " + (e.message||e), "err");
    btn.classList.remove("spin"); btn.textContent="Skapa nytt stall";
  }
}

/* ============ Stall-vy – profiler ============ */
async function renderStable(stableId){
  editingPassId = editingHorseId = editingGroupId = editingCatId = editingProfileId = null;
  stOpen = {};
  stStableId = stableId;
  appEl.innerHTML = `
    <button class="backlink" id="back">‹ Mina stall</button>
    <div class="card"><div id="stableHead"><h1 class="title">Laddar…</h1></div></div>
    <div class="card" id="stTreeCard"><div class="empty">Laddar…</div></div>`;
  el("back").onclick = ()=>{ view={name:"home",stableId:null}; render(); };

  try{
    const st = await db.from("stable").select("*").eq("id", stableId).single();
    if(st.error) throw st.error;
    curAdmin = await amIAdmin(stableId);
    el("stableHead").innerHTML = `
      <div class="schedeyebrow">Inställningar</div>
      <h1 class="schedname" style="margin-bottom:6px">${esc(st.data.name)}</h1>
      <p class="sub" style="margin:0">${curAdmin ? '<span class="pill">Admin</span>' : '<span class="muted">Medlem</span>'}</p>`;
    await reloadStableData();
  }catch(e){
    el("stableHead").innerHTML = msg("Kunde inte öppna stallet: " + (e.message||e), "err");
  }
}

async function amIAdmin(stableId){
  const r = await db.from("stable_admin").select("email").eq("stable_id", stableId).eq("email", session.email).maybeSingle();
  return !r.error && !!r.data;
}

/* ============ Stall-inställningar: trädvy ============ */
let stOpen = {};        // vilka noder i trädet som är öppna
let stStableId = null;
let stData = null;      // {groups, cats, passes, profiles}

async function reloadStableData(){
  const sid = stStableId;
  const [g,c,p,pr] = await Promise.all([
    db.from("duty_group").select("*").eq("stable_id", sid).order("sort_order"),
    db.from("category").select("*").eq("stable_id", sid).order("sort_order"),
    db.from("pass_def").select("*, category(name)").eq("stable_id", sid).order("sort_order"),
    db.from("profile").select("id,name,profile_member(email),horse(id,name,group_id)").eq("stable_id", sid).order("created_at")
  ]);
  const err = g.error || c.error || p.error || pr.error;
  if(err){ el("stTreeCard").innerHTML = msg("Kunde inte hämta stallets data: " + err.message, "err"); return; }
  curGroups = g.data; curCats = c.data;
  stData = { groups: g.data, cats: c.data, passes: sortPassesByTime(p.data), profiles: pr.data };
  renderStableTree();
}

function caret(k){ return `<span class="caret">${stOpen[k]?"▾":"▸"}</span>`; }
function isMyProfile(p){ return (p.profile_member||[]).some(m=> m.email && m.email.toLowerCase() === session.email); }
function tbtns(kind, id, canEdit, canDel){
  if(canEdit === undefined) canEdit = curAdmin;
  if(canDel === undefined) canDel = canEdit;
  if(!canEdit && !canDel) return "";
  return `<span class="tbtns">${canEdit?`<button class="x" data-e="${kind}:${id}" title="Ändra">${ic("pencil")}</button>`:""}${canDel?`<button class="x" data-d="${kind}:${id}" title="Ta bort">${ic("x")}</button>`:""}</span>`;
}

function horseRow(h, mine){
  const may = curAdmin || mine;
  if(may && h.id === editingHorseId){
    const gsel = `<option value="">Ingen grupp</option>` + stData.groups.map(g=>`<option value="${g.id}"${g.id===h.group_id?" selected":""}>${esc(g.name)}</option>`).join("");
    return `<div class="editrow lvl3">
      <div class="field"><label class="fld">Hästens namn</label><input type="text" id="eh_name_${h.id}" value="${esc(h.name||'')}"></div>
      <div class="field"><label class="fld">Grupp</label><select id="eh_group_${h.id}">${gsel}</select></div>
      <div class="editbtns"><button class="btn primary sm" data-s="horse:${h.id}">Spara</button><button class="btn sm" data-c="1">Avbryt</button></div>
    </div>`;
  }
  const g = stData.groups.find(x=>x.id===h.group_id);
  return `<div class="tleaf lvl3"><span class="cdot" style="background:${(g&&g.color)||'#c9d6cd'}"></span><span>${esc(h.name||'Häst')}</span>${tbtns("horse",h.id,may,may)}</div>`;
}

function profileNode(p, groupId, keyPrefix){
  const key = `p_${keyPrefix}_${p.id}`;
  const mine = isMyProfile(p);
  const may = curAdmin || mine;   // får redigera profilen (namn, mejl, hästar)
  const horses = (p.horse||[]).filter(h=> groupId===null ? !h.group_id : h.group_id===groupId);
  const out = [];
  if(may && p.id === editingProfileId){
    out.push(`<div class="editrow lvl2"><div class="editname"><input type="text" id="epr_name_${p.id}" value="${esc(p.name)}">
      <button class="btn primary sm" data-s="profile:${p.id}">Spara</button><button class="btn sm" data-c="1">Avbryt</button></div></div>`);
  } else {
    out.push(`<div class="trow lvl2" data-t="${key}">${ic("user")} ${esc(p.name)}${mine?` <span class="tagpill">du</span>`:""} <span class="meta2">${horses.length} häst${horses.length===1?"":"ar"}</span> ${caret(key)}${tbtns("profile",p.id,may,curAdmin)}</div>`);
  }
  if(stOpen[key]){
    const mails = (p.profile_member||[]).map(m=>m.email).filter(Boolean);
    mails.forEach(em=> out.push(`<div class="tleaf lvl3">${ic("mail")} ${esc(em)}${may?`<span class="tbtns"><button class="x" data-d="mail:${p.id}|${encodeURIComponent(em)}" title="Ta bort">${ic("x")}</button></span>`:""}</div>`));
    if(!mails.length) out.push(`<div class="tleaf lvl3 tmuted">Ingen mejl kopplad än</div>`);
    if(may) out.push(`<div class="addhorse lvl3"><input type="email" id="in_mail_${p.id}" placeholder="Lägg till mejladress"><button class="btn sm" data-add="mail:${p.id}">+ Mejl</button></div>`);
    horses.forEach(h=> out.push(horseRow(h, mine)));
    if(may){
      const gsel = `<option value="">Ingen grupp</option>` + stData.groups.map(g=>`<option value="${g.id}"${g.id===groupId?" selected":""}>${esc(g.name)}</option>`).join("");
      out.push(`<div class="addhorse lvl3"><input type="text" id="in_horse_${keyPrefix}_${p.id}" placeholder="Hästens namn"><select id="in_horsegrp_${keyPrefix}_${p.id}">${gsel}</select><button class="btn sm" data-add="horse:${keyPrefix}:${p.id}">+ Häst</button></div>`);
    }
  }
  return out.join("");
}

function groupNode(g){
  const key = "g_"+g.id;
  const out = [];
  if(curAdmin && g.id === editingGroupId){
    out.push(`<div class="editrow lvl1"><div class="editname"><input type="text" id="eg_name_${g.id}" value="${esc(g.name)}">
      <button class="btn primary sm" data-s="group:${g.id}">Spara</button><button class="btn sm" data-c="1">Avbryt</button></div></div>`);
  } else {
    out.push(`<div class="trow lvl1" data-t="${key}"><span class="cdot" style="background:${g.color||'#4e9e6e'}"></span>${esc(g.name)} ${caret(key)}${tbtns("group",g.id)}</div>`);
  }
  if(stOpen[key]){
    const profs = stData.profiles.filter(p=> (p.horse||[]).some(h=> h.group_id===g.id));
    if(!profs.length) out.push(`<div class="tleaf lvl2 tmuted">Inga hästar i gruppen än</div>`);
    profs.forEach(p=> out.push(profileNode(p, g.id, g.id)));
  }
  return out.join("");
}

function passRow(p){
  if(curAdmin && p.id === editingPassId){
    const catO = `<option value="">Ingen kategori</option>` + stData.cats.map(c=>`<option value="${c.id}"${c.id===p.category_id?" selected":""}>${esc(c.name)}</option>`).join("");
    const dayO = [["all","Alla dagar"],["weekday","Vardagar"],["weekend","Helg"]].map(([v,l])=>`<option value="${v}"${v===p.day_rule?" selected":""}>${l}</option>`).join("");
    const timO = TIME_OPTIONS.map(x=>`<option value="${x}"${x===p.start_time?" selected":""}>${x}</option>`).join("");
    return `<div class="editrow lvl2">
      <div class="field"><label class="fld">Namn</label><input type="text" id="ep_name_${p.id}" value="${esc(p.name)}"></div>
      <div class="field"><label class="fld">Tid</label><select id="ep_time_${p.id}">${timO}</select></div>
      <div class="field"><label class="fld">Kategori</label><select id="ep_cat_${p.id}">${catO}</select></div>
      <div class="field"><label class="fld">Dagar</label><select id="ep_days_${p.id}">${dayO}</select></div>
      <div class="field"><label class="fld">Antal personer</label><select id="ep_cap_${p.id}">${capOpts(p.capacity||1)}</select></div>
      <div class="editbtns"><button class="btn primary sm" data-s="pass:${p.id}">Spara</button><button class="btn sm" data-c="1">Avbryt</button></div>
    </div>`;
  }
  const bits = [p.start_time, DAYLBL[p.day_rule]||"", (p.capacity>1?p.capacity+" pers":"")].filter(Boolean).join(" · ");
  const cat = p.category && p.category.name;
  return `<div class="tleaf lvl2"><span><b>${esc(p.name)}</b> <span class="meta2">${esc(bits)}</span></span>${cat?`<span class="tagpill">${esc(cat)}</span>`:""}${tbtns("pass",p.id)}</div>`;
}

function addPassForm(){
  const catO = `<option value="">Ingen kategori</option>` + stData.cats.map(c=>`<option value="${c.id}">${esc(c.name)}</option>`).join("");
  return `<div class="editrow lvl2">
    <div class="field"><label class="fld">Nytt pass — namn</label><input type="text" id="in_pass_name" placeholder="t.ex. Morgonfodring"></div>
    <div class="field"><label class="fld">Tid</label><select id="in_pass_time">${TIME_OPTIONS.map(t=>`<option value="${t}"${t==="07:00"?" selected":""}>${t}</option>`).join("")}</select></div>
    <div class="field"><label class="fld">Kategori</label><select id="in_pass_cat">${catO}</select></div>
    <div class="field"><label class="fld">Dagar</label><select id="in_pass_days"><option value="all">Alla dagar</option><option value="weekday">Vardagar</option><option value="weekend">Helg</option></select></div>
    <div class="field"><label class="fld">Antal personer</label><select id="in_pass_cap">${capOpts(1)}</select></div>
    <button class="btn primary sm" data-add="pass">+ Lägg till pass</button>
  </div>`;
}

function catRow(c){
  if(curAdmin && c.id === editingCatId){
    return `<div class="editrow lvl2"><div class="editname"><input type="text" id="ec_name_${c.id}" value="${esc(c.name)}">
      <button class="btn primary sm" data-s="cat:${c.id}">Spara</button><button class="btn sm" data-c="1">Avbryt</button></div></div>`;
  }
  return `<div class="tleaf lvl2">${ic("tag")} ${esc(c.name)}${tbtns("cat",c.id)}</div>`;
}

function renderStableTree(){
  const host = el("stTreeCard"); if(!host || !stData) return;
  const t = [];
  t.push(`<div class="trow lvl0" data-t="grupper">${ic("users")} Grupper ${caret("grupper")}</div>`);
  if(stOpen.grupper){
    stData.groups.forEach(g=> t.push(groupNode(g)));
    const loose = stData.profiles.filter(p=> !(p.horse||[]).length || (p.horse||[]).some(h=>!h.group_id));
    if(loose.length){
      t.push(`<div class="trow lvl1" data-t="g_none">◌ Utan grupp ${caret("g_none")}</div>`);
      if(stOpen.g_none) loose.forEach(p=> t.push(profileNode(p, null, "none")));
    }
    if(curAdmin){
      t.push(`<div class="addhorse lvl1"><input type="text" id="in_group" placeholder="Ny grupp"><button class="btn sm" data-add="group">+ Grupp</button></div>`);
      t.push(`<div class="addhorse lvl1"><input type="text" id="in_profile" placeholder="Ny profil, t.ex. Familjen Ek"><button class="btn sm" data-add="profile">+ Profil</button></div>`);
    }
  }
  t.push(`<div class="trow lvl0" data-t="schema">${ic("calendar")} Schema ${caret("schema")}</div>`);
  if(stOpen.schema){
    t.push(`<div class="trow lvl1" data-t="pass">${ic("clock")} Pass ${caret("pass")}</div>`);
    if(stOpen.pass){
      stData.passes.forEach(p=> t.push(passRow(p)));
      if(!stData.passes.length) t.push(`<div class="tleaf lvl2 tmuted">Inga pass än</div>`);
      if(curAdmin) t.push(addPassForm());
    }
    t.push(`<div class="trow lvl1" data-t="kategorier">${ic("tag")} Kategorier ${caret("kategorier")}</div>`);
    if(stOpen.kategorier){
      stData.cats.forEach(c=> t.push(catRow(c)));
      if(!stData.cats.length) t.push(`<div class="tleaf lvl2 tmuted">Inga kategorier än</div>`);
      if(curAdmin) t.push(`<div class="addhorse lvl2"><input type="text" id="in_cat" placeholder="Ny kategori"><button class="btn sm" data-add="cat">+ Kategori</button></div>`);
    }
  }
  host.innerHTML = t.join("");
  host.querySelectorAll("[data-t]").forEach(n=> n.onclick = ()=>{ const k=n.getAttribute("data-t"); stOpen[k]=!stOpen[k]; renderStableTree(); });
  host.querySelectorAll("[data-e]").forEach(b=> b.onclick=(e)=>{ e.stopPropagation(); startEdit(b.getAttribute("data-e")); });
  host.querySelectorAll("[data-d]").forEach(b=> b.onclick=(e)=>{ e.stopPropagation(); doDelete(b.getAttribute("data-d")); });
  host.querySelectorAll("[data-s]").forEach(b=> b.onclick=(e)=>{ e.stopPropagation(); doSave(b.getAttribute("data-s")); });
  host.querySelectorAll("[data-c]").forEach(b=> b.onclick=(e)=>{ e.stopPropagation(); cancelEdit(); });
  host.querySelectorAll("[data-add]").forEach(b=> b.onclick=(e)=>{ e.stopPropagation(); doAdd(b.getAttribute("data-add")); });
  host.querySelectorAll(".addhorse, .editrow").forEach(n=> n.onclick=(e)=> e.stopPropagation());
}

function startEdit(spec){
  const [kind,id] = spec.split(":");
  editingPassId = editingHorseId = editingGroupId = editingCatId = editingProfileId = null;
  if(kind==="pass") editingPassId = id;
  if(kind==="horse") editingHorseId = id;
  if(kind==="group") editingGroupId = id;
  if(kind==="cat") editingCatId = id;
  if(kind==="profile") editingProfileId = id;
  renderStableTree();
}
function cancelEdit(){ editingPassId = editingHorseId = editingGroupId = editingCatId = editingProfileId = null; renderStableTree(); }

function confirmDialog(text){
  return new Promise(res=>{
    const ov = document.createElement("div"); ov.className = "modal-ov";
    ov.innerHTML = `<div class="modal"><h3>Är du säker?</h3><p>${esc(text)}</p>
      <div class="modal-btns"><button class="btn" id="mCancel">Avbryt</button><button class="btn danger-solid" id="mOk">Ja, ta bort</button></div></div>`;
    document.body.appendChild(ov);
    const done = v => { ov.remove(); res(v); };
    ov.querySelector("#mCancel").onclick = ()=> done(false);
    ov.querySelector("#mOk").onclick = ()=> done(true);
    ov.onclick = (e)=>{ if(e.target===ov) done(false); };
  });
}

async function doDelete(spec){
  const i = spec.indexOf(":"); const kind = spec.slice(0,i); const id = spec.slice(i+1);
  let q = null, text = "";
  if(kind==="group"){ const g=stData.groups.find(x=>x.id===id); text=`Du håller på att ta bort gruppen "${g?g.name:""}". Hästar i gruppen blir utan grupp.`; q=()=>db.from("duty_group").delete().eq("id",id); }
  if(kind==="profile"){ const p=stData.profiles.find(x=>x.id===id); text=`Du håller på att ta bort profilen "${p?p.name:""}" med alla dess hästar och bokningar.`; q=()=>db.from("profile").delete().eq("id",id); }
  if(kind==="horse"){ let hn="Häst"; stData.profiles.forEach(p=>(p.horse||[]).forEach(h=>{ if(h.id===id) hn=h.name||"Häst"; })); text=`Du håller på att ta bort hästen "${hn}".`; q=()=>db.from("horse").delete().eq("id",id); }
  if(kind==="mail"){ const j=id.indexOf("|"); const pid=id.slice(0,j); const email=decodeURIComponent(id.slice(j+1)); text=`Du håller på att ta bort mejladressen ${email} från profilen.`; q=()=>db.from("profile_member").delete().eq("profile_id",pid).eq("email",email); }
  if(kind==="pass"){ const p=stData.passes.find(x=>x.id===id); text=`Du håller på att ta bort passet "${p?p.name:""}". Alla bokningar på passet försvinner.`; q=()=>db.from("pass_def").delete().eq("id",id); }
  if(kind==="cat"){ const c=stData.cats.find(x=>x.id===id); text=`Du håller på att ta bort kategorin "${c?c.name:""}". Pass i kategorin blir utan kategori.`; q=()=>db.from("category").delete().eq("id",id); }
  if(!q) return;
  if(!(await confirmDialog(text))) return;
  const r = await q();
  if(r.error){ alert("Kunde inte ta bort: " + r.error.message); return; }
  await reloadStableData();
}

async function doSave(spec){
  const [kind,id] = spec.split(":");
  let r = null;
  if(kind==="group"){ const name=(el("eg_name_"+id).value||"").trim(); if(!name) return; r=await db.from("duty_group").update({name}).eq("id",id); }
  if(kind==="profile"){ const name=(el("epr_name_"+id).value||"").trim(); if(!name) return; r=await db.from("profile").update({name}).eq("id",id); }
  if(kind==="cat"){ const name=(el("ec_name_"+id).value||"").trim(); if(!name) return; r=await db.from("category").update({name}).eq("id",id); }
  if(kind==="horse"){ r=await db.from("horse").update({ name:(el("eh_name_"+id).value||"").trim()||null, group_id: el("eh_group_"+id).value||null }).eq("id",id); }
  if(kind==="pass"){
    let cap=parseInt(el("ep_cap_"+id).value,10); if(isNaN(cap)||cap<1) cap=1;
    r=await db.from("pass_def").update({ name:el("ep_name_"+id).value.trim()||"Pass", start_time:el("ep_time_"+id).value, category_id:el("ep_cat_"+id).value||null, day_rule:el("ep_days_"+id).value, capacity:cap }).eq("id",id);
  }
  if(!r) return;
  if(r.error){ alert("Kunde inte spara: " + r.error.message); return; }
  editingPassId = editingHorseId = editingGroupId = editingCatId = editingProfileId = null;
  await reloadStableData();
}

async function doAdd(spec){
  const parts = spec.split(":"); const kind = parts[0], a = parts[1], b = parts[2];
  let r = null;
  if(kind==="group"){ const name=(el("in_group").value||"").trim(); if(!name) return;
    r = await db.from("duty_group").insert({ stable_id:stStableId, name, color:GROUP_GREENS[stData.groups.length % GROUP_GREENS.length], sort_order:stData.groups.length }); }
  if(kind==="profile"){ const name=(el("in_profile").value||"").trim(); if(!name) return;
    r = await db.from("profile").insert({ stable_id:stStableId, name }); }
  if(kind==="cat"){ const name=(el("in_cat").value||"").trim(); if(!name) return;
    r = await db.from("category").insert({ stable_id:stStableId, name, sort_order:stData.cats.length }); }
  if(kind==="mail"){ const email=normEmail(el("in_mail_"+a).value); if(!email.includes("@")){ alert("Skriv en giltig mejladress."); return; }
    r = await db.from("profile_member").insert({ profile_id:a, email }); }
  if(kind==="horse"){ const name=(el("in_horse_"+a+"_"+b).value||"").trim(); const gid=el("in_horsegrp_"+a+"_"+b).value||null;
    r = await db.from("horse").insert({ profile_id:b, name:name||null, group_id:gid }); }
  if(kind==="pass"){ const name=(el("in_pass_name").value||"").trim(); if(!name) return;
    let cap=parseInt(el("in_pass_cap").value,10); if(isNaN(cap)||cap<1) cap=1;
    r = await db.from("pass_def").insert({ stable_id:stStableId, name, start_time:el("in_pass_time").value, category_id:el("in_pass_cat").value||null, day_rule:el("in_pass_days").value, capacity:cap, sort_order:stData.passes.length }); }
  if(!r) return;
  if(r.error){ alert("Kunde inte lägga till: " + r.error.message); return; }
  await reloadStableData();
}

/* ============ Pass-hjälpare ============ */
const DAYLBL = { all:"Alla dagar", weekday:"Vardagar", weekend:"Helg", weekdays:"Valda dagar" };
/* ============ Schema-vy ============ */
async function renderSchedule(stableId){
  appEl.innerHTML = `<button class="backlink" id="backSch">‹ Tillbaka till stallet</button><div id="schShell"><div class="card"><div class="empty">Laddar schema…</div></div></div>`;
  el("backSch").onclick = ()=>{ view={name:"stable",stableId}; render(); };
  try{
    const st = await db.from("stable").select("*").eq("id", stableId).single(); if(st.error) throw st.error;
    const g  = await db.from("duty_group").select("*").eq("stable_id", stableId).order("sort_order"); if(g.error) throw g.error;
    const p  = await db.from("pass_def").select("*, category(name)").eq("stable_id", stableId).order("sort_order"); if(p.error) throw p.error;
    const pr = await db.from("profile").select("id,name,horse(id,group_id)").eq("stable_id", stableId).order("created_at"); if(pr.error) throw pr.error;
    const mp = await db.from("profile_member").select("profile(id,name,stable_id)").eq("email", session.email); if(mp.error) throw mp.error;
    const myProfiles = (mp.data||[]).map(r=>r.profile).filter(x=> x && x.stable_id===stableId);
    schedCtx = { stable: st.data, groups: g.data, passes: sortPassesByTime(p.data), profiles: pr.data, myProfiles, actingProfileId: myProfiles[0] ? myProfiles[0].id : null };
    if(!weekStart2) weekStart2 = startOfWeek(new Date());
    drawScheduleShell();
    await drawGrid();
  }catch(e){ el("schShell").innerHTML = msg("Kunde inte öppna schemat: " + (e.message||e), "err"); }
}

function drawScheduleShell(){
  const mp = schedCtx.myProfiles;
  const hint = mp.length ? "" :
    `<div class="hint">Du har ingen egen profil i det här stallet, så du kan se schemat men inte boka. Be admin lägga in din mejl på en profil.</div>`;
  el("schShell").innerHTML = `
    <div class="card">
      <div class="schedeyebrow">Schema</div>
      <h1 class="schedname">${esc(schedCtx.stable.name)}</h1>
      <div id="weeknav"></div>
      ${hint}
    </div>
    <div id="gridHost"></div>`;
  drawWeekNav();
}

function drawWeekNav(){
  const end = new Date(weekStart2); end.setDate(end.getDate()+6);
  const duty = dutyGroupForWeek(weekStart2, schedCtx.groups, schedCtx.stable.rotation_offset);
  el("weeknav").innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
      <button class="btn sm" id="wPrev">‹ Förra</button>
      <button class="btn sm" id="wWeek" title="Till nuvarande vecka">Vecka ${isoWeekNumber(weekStart2)}</button>
      <button class="btn sm" id="wNext">Nästa ›</button>
      <div style="flex:1"></div>
      <div class="muted" style="font-size:.82rem;text-align:right">${weekStart2.getDate()} ${MONTHS[weekStart2.getMonth()]} – ${end.getDate()} ${MONTHS[end.getMonth()]} · ${weekStart2.getFullYear()}</div>
    </div>
    ${duty?`<div style="margin-top:8px"><span class="dutychip" style="background:${duty.color||'#4e9e6e'}">${esc(duty.name)}</span></div>`:""}`;
  el("wPrev").onclick = ()=> shiftWeek2(-1);
  el("wNext").onclick = ()=> shiftWeek2(1);
  el("wWeek").onclick = ()=>{ weekStart2 = startOfWeek(new Date()); drawWeekNav(); drawGrid(); };
}
function shiftWeek2(n){ weekStart2 = new Date(weekStart2); weekStart2.setDate(weekStart2.getDate()+n*7); drawWeekNav(); drawGrid(); }

async function drawGrid(keepScroll){
  const host = el("gridHost");
  const scrollY = window.scrollY;
  if(!keepScroll) host.innerHTML = `<div class="card"><div class="empty">Laddar…</div></div>`;
  const days = []; for(let i=0;i<7;i++){ const d=new Date(weekStart2); d.setDate(d.getDate()+i); days.push(d); }
  const startISO = isoDate(days[0]), endISO = isoDate(days[6]);
  const b = await db.from("booking").select("id,pass_id,pass_date,profile_id,booked_by,profile(name)")
    .eq("stable_id", schedCtx.stable.id).gte("pass_date", startISO).lte("pass_date", endISO);
  if(b.error){ host.innerHTML = msg("Kunde inte hämta bokningar: " + b.error.message, "err"); return; }
  const map = {};
  (b.data||[]).forEach(bk=>{ const k = bk.pass_id+"|"+bk.pass_date; (map[k]=map[k]||[]).push(bk); });

  const duty = dutyGroupForWeek(weekStart2, schedCtx.groups, schedCtx.stable.rotation_offset);
  const myIds = new Set(schedCtx.myProfiles.map(p=>p.id));
  const passes = schedCtx.passes;
  const tISO = isoDate(new Date());

  // Måltal per profil (viktat efter hästar) + faktiskt bokade denna vecka
  const tgt = computeTargets(weekStart2);
  if(tgt){
    const passCat = {}; passes.forEach(p=> passCat[p.id] = p.category_id || "none");
    (b.data||[]).forEach(bk=>{
      const prof = tgt.perProfile[bk.profile_id]; if(!prof) return;
      const key = passCat[bk.pass_id] || "none";
      if(!prof.byCat[key]) prof.byCat[key] = { name:(tgt.cats[key]?tgt.cats[key].name:"Övrigt"), target:0, actual:0 };
      prof.byCat[key].actual++;
    });
  }

  let html = `<div class="card schedcard" style="overflow-x:auto"><div class="sgrid" style="--cols:${passes.length}">`;
  // rubrikrad: hörn + pass (vågrätt)
  html += `<div class="scorner"></div>`;
  passes.forEach(p=>{
    html += `<div class="sph"><span class="pn">${esc(p.name)}</span><span class="pt">${esc(p.start_time||"")}${p.capacity>1?" · "+p.capacity+"p":""}</span></div>`;
  });
  // en rad per veckodag (lodrätt)
  days.forEach(d=>{
    const dISO = isoDate(d);
    const wknd = (d.getDay()===0 || d.getDay()===6);
    const applicable = passes.filter(p=> passApplies(p, d));
    const dayDone = applicable.length > 0 && applicable.every(p=> (map[p.id+"|"+dISO]||[]).length >= (p.capacity||1));
    html += `<div class="sdl${dISO===tISO?" today":""}${wknd?" weekend":""}${dayDone?" done":""}"><span class="dn">${SHORT_DAYS[d.getDay()]}</span><span class="dd">${d.getDate()}/${d.getMonth()+1}</span></div>`;
    passes.forEach(p=>{ html += scheduleCell(p, d, dISO, map, myIds, tISO); });
  });
  html += `</div></div>`;
  html += renderStats(tgt, myIds);   // statistiken under schemat
  host.innerHTML = html;
  if(keepScroll) window.scrollTo(0, scrollY);

  host.querySelectorAll("[data-book]").forEach(btn=> btn.onclick = ()=> bookCell(btn.getAttribute("data-book"), btn.getAttribute("data-date")));
  host.querySelectorAll("[data-cancel]").forEach(btn=> btn.onclick = ()=> cancelBooking(btn.getAttribute("data-cancel")));
}

function scheduleCell(p, d, dISO, map, myIds, tISO){
  if(!passApplies(p, d)) return `<div class="scell na">·</div>`;
  const list = map[p.id+"|"+dISO] || [];
  const cap = p.capacity || 1;
  const full = list.length >= cap;
  const isPast = dISO < tISO;
  const mineHere = list.some(bk=> myIds.has(bk.profile_id));
  const canBook = schedCtx.actingProfileId && !full && !isPast;
  const chips = list.map(bk=>{
    const mine = myIds.has(bk.profile_id);
    return `<span class="schip">${esc((bk.profile&&bk.profile.name)||"?")}${(mine&&!isPast)?`<button class="x2" data-cancel="${bk.id}" title="Avboka">✕</button>`:""}</span>`;
  }).join("");
  const empty = (!list.length && !canBook) ? `<span class="sempty">–</span>` : "";
  const badge = cap>1 ? `<span class="scap ${full?"ok":"need"}">${list.length}/${cap}</span>` : "";
  const btn = canBook ? `<button class="sbook" data-book="${p.id}" data-date="${dISO}" title="Ta pass">+</button>` : "";
  return `<div class="scell${mineHere?" mine":""}${isPast?" past":""}">
      ${badge?`<div class="scaprow">${badge}</div>`:""}
      <div class="schips">${chips}${empty}</div>
      ${btn}
    </div>`;
}

async function bookCell(passId, dISO){
  const pid = schedCtx.actingProfileId; if(!pid) return;
  const pass = schedCtx.passes.find(x=>x.id===passId); const cap = pass ? (pass.capacity||1) : 1;
  const cur = await db.from("booking").select("id").eq("pass_id", passId).eq("pass_date", dISO);
  if(!cur.error && cur.data.length >= cap){ await drawGrid(); return; }
  const r = await db.from("booking").insert({ stable_id: schedCtx.stable.id, pass_id: passId, pass_date: dISO, profile_id: pid, booked_by: session.id });
  if(r.error){ alert("Kunde inte boka: " + r.error.message); return; }
  await drawGrid(true);
}
async function cancelBooking(id){
  const r = await db.from("booking").delete().eq("id", id);
  if(r.error){ alert("Kunde inte avboka: " + r.error.message); return; }
  await drawGrid(true);
}

/* ---- Rättvis fördelning: måltal per profil, viktat efter hästar ---- */
// Totalt antal platser per kategori under veckan som börjar på "monday".
function categoryTotals(monday){
  const days = []; for(let i=0;i<7;i++){ const d=new Date(monday); d.setDate(d.getDate()+i); days.push(d); }
  const totals = {};
  schedCtx.passes.forEach(p=>{
    let applicableDays = 0;
    days.forEach(d=>{ if(passApplies(p, d)) applicableDays++; });
    const platser = applicableDays * (p.capacity || 1);
    if(platser === 0) return;
    const key = p.category_id || "none";
    const name = (p.category && p.category.name) || "Övrigt";
    if(!totals[key]) totals[key] = { name, total:0 };
    totals[key].total += platser;
  });
  return totals;
}

// Vilken gång i ordningen har gruppen jobbat (0, 1, 2 …) – styr rotationen av extrapass.
function groupTurnNumber(monday){
  const n = schedCtx.groups.length; if(!n) return 0;
  return Math.floor((weekIndexOf(monday) + (schedCtx.stable.rotation_offset||0)) / n);
}

function computeTargets(monday){
  const duty = dutyGroupForWeek(monday, schedCtx.groups, schedCtx.stable.rotation_offset);
  if(!duty) return null;
  // Hästar i den ansvariga gruppen (en häst = en enhet), stabil ordning.
  const horses = [];
  (schedCtx.profiles||[]).forEach(pr=>{
    (pr.horse||[]).forEach(h=>{ if(h.group_id === duty.id) horses.push({ id:h.id, profileId:pr.id, profileName:pr.name }); });
  });
  horses.sort((a,b)=> a.id < b.id ? -1 : (a.id > b.id ? 1 : 0));
  const nH = horses.length;
  const turn = groupTurnNumber(monday);
  const cats = categoryTotals(monday);

  const perProfile = {};
  horses.forEach(h=>{ if(!perProfile[h.profileId]) perProfile[h.profileId] = { name:h.profileName, byCat:{} }; });

  if(nH > 0){
    Object.keys(cats).forEach(catKey=>{
      const total = cats[catKey].total;
      const base = Math.floor(total / nH);
      const rem  = total % nH;
      // extrapassen går till "rem" hästar, med startpunkt som roterar per gruppens tur
      const start = rem > 0 ? (((turn * rem) % nH) + nH) % nH : 0;
      const extra = new Set();
      for(let k=0;k<rem;k++) extra.add((start + k) % nH);
      horses.forEach((h, idx)=>{
        const t = base + (extra.has(idx) ? 1 : 0);
        const pc = perProfile[h.profileId].byCat;
        if(!pc[catKey]) pc[catKey] = { name:cats[catKey].name, target:0, actual:0 };
        pc[catKey].target += t;
      });
    });
  }
  return { duty, perProfile, cats };
}

function renderStats(tgt, myIds){
  if(!tgt) return "";
  const pids = Object.keys(tgt.perProfile);
  if(!pids.length) return `<div class="card"><p class="sub" style="margin:0">Inga hästar i ${esc(tgt.duty.name)} den här veckan.</p></div>`;
  const catKeys = Object.keys(tgt.cats).filter(k=> tgt.cats[k].total > 0);
  const rows = pids.map(pid=>{
    const pr = tgt.perProfile[pid];
    const mine = myIds.has(pid);
    const chips = catKeys.map(k=>{
      const c = pr.byCat[k] || { name:tgt.cats[k].name, target:0, actual:0 };
      const done = c.target > 0 && c.actual >= c.target;
      return `<span class="statcat ${done?"done":""}">${esc(c.name)} ${c.actual}/${c.target}</span>`;
    }).join("");
    return `<div class="statrow${mine?" me":""}"><span class="sn">${esc(pr.name)}</span>${chips}</div>`;
  }).join("");
  return `<div class="card">
    <p class="sub" style="margin:0 0 8px">Måltal denna vecka <span class="sectionhint">— ${esc(tgt.duty.name)}, viktat efter hästar</span></p>
    <div class="statwrap">${rows}</div></div>`;
}

/* ============ Toppknappar: Profil, Inställningar, Tema ============ */
let theme = (()=>{ try{ return localStorage.getItem("stalljour.theme")||"light"; }catch(e){ return "light"; } })();
function applyTheme(t){
  document.documentElement.setAttribute("data-theme", t==="dark" ? "dark" : "light");
  const b = el("btnTheme"); if(b) b.innerHTML = ic(t==="dark" ? "sun" : "moon");
}
applyTheme(theme);
el("btnTheme").onclick = ()=>{ theme = theme==="dark"?"light":"dark"; try{ localStorage.setItem("stalljour.theme", theme); }catch(e){} applyTheme(theme); };

function updateHeader(){
  el("btnProfile").style.display  = session ? "" : "none";
  el("btnSchedule").style.display = session ? "" : "none";
  el("btnSettings").style.display = session ? "" : "none";
}

function closeMenus(){ el("profileMenu").classList.remove("open"); el("scheduleMenu").classList.remove("open"); }
function closeProfileMenu(){ closeMenus(); }

let pmState = null;   // utfällnings-läge för profil-menyn
function resetPmState(){ pmState = { stablesOpen:false, stables:null, openStableId:null, profilesOpen:false, myProfiles:null }; }

function buildProfileMenu(){
  const m = el("profileMenu");
  let bookAs = "";
  if(view.name === "schedule" && schedCtx && schedCtx.myProfiles.length){
    bookAs = `<div class="menuhead sub">Bokar som</div>` + schedCtx.myProfiles.map(p=>
      `<button class="menuitem" data-bookas="${p.id}">${p.id===schedCtx.actingProfileId?"✓ ":""}${esc(p.name)}</button>`).join("");
  }
  // Mina stall (nivå 1) -> stall (nivå 2) -> Mina profiler (nivå 3) -> profilnamn
  let tree = `<button class="menuitem" data-pm="stables">${ic("home")} Mina stall <span class="caret">${pmState.stablesOpen?"▾":"▸"}</span></button>`;
  if(pmState.stablesOpen){
    if(!pmState.stables) tree += `<div class="menuhead sub">Laddar…</div>`;
    else if(!pmState.stables.length) tree += `<div class="menuhead sub">Inga stall än</div>`;
    else pmState.stables.forEach(s=>{
      const open = pmState.openStableId === s.id;
      tree += `<button class="menuitem sub1" data-pmstable="${s.id}">${esc(s.name)} <span class="caret">${open?"▾":"▸"}</span></button>`;
      if(open){
        tree += `<button class="menuitem sub2" data-pm="profiles">${ic("users")} Mina profiler <span class="caret">${pmState.profilesOpen?"▾":"▸"}</span></button>`;
        if(pmState.profilesOpen){
          if(!pmState.myProfiles) tree += `<div class="menuhead sub">Laddar…</div>`;
          else if(!pmState.myProfiles.length) tree += `<div class="pmleaf muted">Inga profiler kopplade till din mejl</div>`;
          else pmState.myProfiles.forEach(p=> tree += `<div class="pmleaf">• ${esc(p.name)}</div>`);
        }
      }
    });
  }
  m.innerHTML = `
    <div class="menuhead">${esc(session.email)}</div>
    ${bookAs}
    ${tree}
    <button class="menuitem" data-act="newstable">${ic("plus")} Nytt stall</button>
    <button class="menuitem" data-act="logout">${ic("logout")} Logga ut</button>`;
  m.querySelectorAll("[data-act]").forEach(b=> b.onclick = ()=> profileAction(b.getAttribute("data-act")));
  m.querySelectorAll("[data-bookas]").forEach(b=> b.onclick = ()=>{
    schedCtx.actingProfileId = b.getAttribute("data-bookas");
    closeProfileMenu();
    drawGrid(true);
  });
  m.querySelectorAll("[data-pm]").forEach(b=> b.onclick = (e)=>{
    e.stopPropagation();
    const k = b.getAttribute("data-pm");
    if(k === "stables"){
      pmState.stablesOpen = !pmState.stablesOpen;
      if(pmState.stablesOpen && !pmState.stables){
        loadMyStables().then(s=>{ pmState.stables = s; buildProfileMenu(); }).catch(()=>{ pmState.stables = []; buildProfileMenu(); });
      }
    }
    if(k === "profiles"){
      pmState.profilesOpen = !pmState.profilesOpen;
      if(pmState.profilesOpen && !pmState.myProfiles){
        db.from("profile_member").select("profile(id,name,stable_id)").eq("email", session.email).then(r=>{
          pmState.myProfiles = (r.data||[]).map(x=>x.profile).filter(p=> p && p.stable_id === pmState.openStableId);
          buildProfileMenu();
        });
      }
    }
    buildProfileMenu();
  });
  m.querySelectorAll("[data-pmstable]").forEach(b=> b.onclick = (e)=>{
    e.stopPropagation();
    const id = b.getAttribute("data-pmstable");
    pmState.openStableId = pmState.openStableId === id ? null : id;
    pmState.profilesOpen = false; pmState.myProfiles = null;
    buildProfileMenu();
  });
}
async function profileAction(act){
  closeProfileMenu();
  if(act==="newstable"){ didAutoRoute = true; view = { name:"home", stableId:null }; render(); return; }
  if(act==="logout"){ await db.auth.signOut(); view = { name:"home", stableId:null }; return; }
}
el("btnProfile").onclick = (e)=>{
  e.stopPropagation();
  const m = el("profileMenu");
  const wasOpen = m.classList.contains("open");
  closeMenus();
  if(!wasOpen){ resetPmState(); buildProfileMenu(); m.classList.add("open"); }
};
document.addEventListener("click", (e)=>{ if(!e.target.closest(".menuwrap")) closeMenus(); });

async function gotoView(name){
  closeProfileMenu();
  if(!session) return;
  if(name==="schedule") weekStart2 = startOfWeek(new Date());
  if(view.stableId){ view = { name, stableId: view.stableId }; render(); return; }
  try{
    const stables = await loadMyStables();
    if(stables.length === 1){ view = { name, stableId: stables[0].id }; }
    else { view = { name:"home", stableId:null }; }
    render();
  }catch(e){ view = { name:"home", stableId:null }; render(); }
}
el("btnSettings").onclick = ()=> gotoView("stable");

// Schema-knappen: ett stall → gå direkt; flera → dropdown för att välja stall
async function openScheduleMenu(){
  const m = el("scheduleMenu");
  m.innerHTML = `<div class="menuhead sub">Laddar…</div>`;
  m.classList.add("open");
  try{
    const stables = await loadMyStables();
    if(stables.length <= 1){
      closeMenus();
      if(stables.length === 1){ weekStart2 = startOfWeek(new Date()); view = { name:"schedule", stableId: stables[0].id }; render(); }
      return;
    }
    m.innerHTML = `<div class="menuhead">Välj stall</div>` + stables.map(s=>
      `<button class="menuitem" data-sched="${s.id}">${view.stableId===s.id?"✓ ":""}${esc(s.name)}</button>`).join("");
    m.querySelectorAll("[data-sched]").forEach(b=> b.onclick = ()=>{
      closeMenus();
      weekStart2 = startOfWeek(new Date());
      view = { name:"schedule", stableId: b.getAttribute("data-sched") };
      render();
    });
  }catch(e){ m.innerHTML = `<div class="menuhead sub">Kunde inte hämta stall</div>`; }
}
el("btnSchedule").onclick = (e)=>{
  e.stopPropagation();
  const m = el("scheduleMenu");
  const wasOpen = m.classList.contains("open");
  closeMenus();
  if(!wasOpen) openScheduleMenu();
};

/* ============ Ikoner i headern ============ */
document.querySelectorAll(".islot").forEach(s=>{ s.outerHTML = ic(s.getAttribute("data-icon")); });

/* ============ Start ============ */
function setSessionFrom(s){ session = s ? { id: s.user.id, email: normEmail(s.user.email) } : null; }
db.auth.onAuthStateChange((_event, s)=>{ setSessionFrom(s); render(); });
db.auth.getSession().then(({ data })=>{ setSessionFrom(data.session); render(); });
