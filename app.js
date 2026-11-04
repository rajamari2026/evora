const SB = 'https://qixnxntmaeeeyetwsgdy.supabase.co', KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFpeG54bnRtYWVlZXlldHdzZ2R5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyNzE0ODEsImV4cCI6MjEwODg0NzQ4MX0.FIAPEiucXRikt9PdNtgUc5wCO1TMaCaUTkUfaKbHCeg';
const LOGO = document.querySelector('link[rel=icon]').href;
const $ = (s) => document.querySelector(s);

function el(tag, props, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (k === 'class') e.className = v;
    else if (k === 'text') e.textContent = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v);
  }
  for (const c of kids.flat()) if (c != null) e.append(c.nodeType ? c : document.createTextNode(c));
  return e;
}
function toast(msg) { const t = $('#toast'); t.textContent = msg; t.style.display = 'block'; clearTimeout(toast.t); toast.t = setTimeout(() => t.style.display = 'none', 3200); }
const nameOf = (email) => { const u = (email || '').split('@')[0] || '?'; return u.charAt(0).toUpperCase() + u.slice(1); };
const safe = (s) => (s || 'photos').replace(/[^\w\- ]+/g, '_');

// ---------- session ----------
let session = JSON.parse(localStorage.getItem('evora_session') || 'null');
function save(s) { session = s; s ? localStorage.setItem('evora_session', JSON.stringify(s)) : localStorage.removeItem('evora_session'); }
async function auth(path, body) {
  const r = await fetch(SB + '/auth/v1/' + path, { method: 'POST', headers: { apikey: KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.msg || j.error_description || j.message || 'Error ' + r.status);
  return j;
}
function setSession(j) {
  if (!j.access_token) throw new Error('Account created. Confirm your email, then sign in.');
  save({ access: j.access_token, refresh: j.refresh_token, email: (j.user.email || '').toLowerCase(), uid: j.user.id });
}
async function refresh() {
  if (!session) return false;
  try { setSession(await auth('token?grant_type=refresh_token', { refresh_token: session.refresh })); return true; }
  catch (e) { save(null); return false; }
}
async function api(path, opts = {}, retry = true) {
  const r = await fetch(SB + path, { ...opts, headers: { apikey: KEY, Authorization: 'Bearer ' + session.access, ...(opts.headers || {}) } });
  if (r.status === 401 && retry && await refresh()) return api(path, opts, false);
  if (r.status === 401) { save(null); render(); throw new Error('Signed out'); }
  return r;
}

async function signOut() {
  const token = session && session.access;
  save(null); shares = []; album = null; render();
  // Revoke the refresh token server-side so a copied session can't be reused.
  if (token) fetch(SB + '/auth/v1/logout', { method: 'POST', headers: { apikey: KEY, Authorization: 'Bearer ' + token } }).catch(() => {});
}

// ---------- data ----------
let shares = [], tab = 'shared', album = null, loading = false;
const incoming = () => shares.filter((s) => s.owner_id !== session.uid);
async function loadShares() {
  loading = true; render();
  try {
    const r = await api('/rest/v1/shares?select=*&order=created_at.desc');
    if (!r.ok) throw new Error((await r.json()).message || 'Could not load shares');
    shares = await r.json();
  } catch (e) { toast(e.message); }
  loading = false; render();
}
async function respond(id, accept) {
  const r = await api('/rest/v1/rpc/respond_share', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ p_share_id: id, p_accept: accept }) });
  if (!r.ok) toast((await r.json()).message || 'Could not answer'); else toast(accept ? 'Accepted. You can now view the photos.' : 'Declined.');
  await loadShares();
}

// ---------- photos ----------
const blobCache = new Map();
const thumbOf = (p) => p.replace(/\/(\d+)\.jpg$/, '/t$1.jpg');
function fetchBlobUrl(path) {
  if (!blobCache.has(path)) {
    blobCache.set(path, (async () => {
      const r = await api('/storage/v1/object/authenticated/shared/' + path);
      if (!r.ok) throw new Error('missing');
      return URL.createObjectURL(await r.blob());
    })());
  }
  return blobCache.get(path);
}
async function thumbUrl(path) { try { return await fetchBlobUrl(thumbOf(path)); } catch (e) { return fetchBlobUrl(path); } }
async function saveFile(path, name) {
  const r = await api('/storage/v1/object/authenticated/shared/' + path);
  if (!r.ok) { toast('Could not download'); return; }
  const url = URL.createObjectURL(await r.blob());
  const a = el('a', { href: url, download: name }); document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}
function loadScript(src, integrity) { return new Promise((res, rej) => { const s = document.createElement('script'); s.src = src; if (integrity) { s.integrity = integrity; s.crossOrigin = 'anonymous'; } s.onload = res; s.onerror = rej; document.head.append(s); }); }
async function downloadAll(btn) {
  const { share, paths } = album;
  const old = btn.textContent; btn.disabled = true;
  try {
    if (!window.JSZip) await loadScript('https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js', 'sha512-XMVd28F1oH/O71fzwBnV7HucLxVwtxf26XV8P4wPk26EDxuGZ91N8bsOttmnomcCD3CS5ZMRL50H0GgOHvegtg==');
    const zip = new JSZip();
    for (let i = 0; i < paths.length; i++) {
      btn.textContent = 'Preparing ' + (i + 1) + ' / ' + paths.length;
      const r = await api('/storage/v1/object/authenticated/shared/' + paths[i]);
      if (r.ok) zip.file(safe(share.title) + '-' + (i + 1) + '.jpg', await r.blob());
    }
    btn.textContent = 'Creating ZIP...';
    const blob = await zip.generateAsync({ type: 'blob', compression: 'STORE' });
    const url = URL.createObjectURL(blob);
    const a = el('a', { href: url, download: safe(share.title) + '.zip' }); document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 8000);
  } catch (e) { toast('Could not create the ZIP. Try downloading single photos.'); }
  btn.textContent = old; btn.disabled = false;
}

// ---------- lightbox ----------
let lbIndex = 0;
async function openLb(i) {
  lbIndex = (i + album.paths.length) % album.paths.length;
  $('#lb').classList.add('on');
  $('#lbCount').textContent = (lbIndex + 1) + ' / ' + album.paths.length;
  $('#lbDl').style.display = album.share.allow_download ? '' : 'none';
  const img = $('#lbImg'); img.removeAttribute('src');
  const idx = lbIndex;
  try { const u = await fetchBlobUrl(album.paths[idx]); if (idx === lbIndex) img.src = u; } catch (e) { toast('Could not open this photo'); }
}
$('#lbClose').onclick = () => $('#lb').classList.remove('on');
$('#lbPrev').onclick = () => openLb(lbIndex - 1);
$('#lbNext').onclick = () => openLb(lbIndex + 1);
$('#lbDl').onclick = () => saveFile(album.paths[lbIndex], safe(album.share.title) + '-' + (lbIndex + 1) + '.jpg');
document.addEventListener('keydown', (e) => {
  if (!$('#lb').classList.contains('on')) return;
  if (e.key === 'Escape') $('#lb').classList.remove('on');
  if (e.key === 'ArrowLeft') openLb(lbIndex - 1);
  if (e.key === 'ArrowRight') openLb(lbIndex + 1);
});

// ---------- views ----------
const app = $('#app');
function header() {
  return el('header', {},
    el('img', { src: LOGO, alt: '' }), el('h1', { text: 'Evora' }),
    session ? el('span', { class: 'dim', text: session.email }) : null,
    session ? el('button', { class: 'btn ghost', text: 'Refresh', onclick: loadShares }) : null,
    session ? el('button', { class: 'btn ghost', text: 'Sign out', onclick: signOut }) : null);
}

function loginView() {
  let create = false;
  const email = el('input', { type: 'email', placeholder: 'Email', autocomplete: 'username' });
  const pass = el('input', { type: 'password', placeholder: 'Password', autocomplete: 'current-password' });
  const err = el('div', { class: 'err' });
  const go = el('button', { class: 'btn', text: 'Sign in', style: 'width:100%;margin-top:16px' });
  const sw = el('button', { class: 'btn ghost', text: 'Create a new account', style: 'width:100%;margin-top:10px' });
  async function submit() {
    err.textContent = ''; go.disabled = true;
    try {
      const body = { email: email.value.trim().toLowerCase(), password: pass.value };
      setSession(await auth(create ? 'signup' : 'token?grant_type=password', body));
      await loadShares();
    } catch (e) { err.textContent = e.message; }
    go.disabled = false;
  }
  go.onclick = submit;
  pass.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
  sw.onclick = () => { create = !create; go.textContent = create ? 'Create account' : 'Sign in'; sw.textContent = create ? 'I already have an account' : 'Create a new account'; };
  return el('div', { class: 'glass login' },
    el('h2', { text: 'Sign in to Evora' }),
    el('div', { class: 'dim', text: 'Use the same email and password as in the Evora app. You see photos only after you accept them.' }),
    email, pass, err, go, sw);
}

function accessPill(s) { return el('span', { class: 'pill ' + (s.allow_download ? 'ok' : ''), text: s.allow_download ? 'Download allowed' : 'View only' }); }

function requestCard(s) {
  return el('div', { class: 'glass card', style: 'cursor:default' },
    el('div', { class: 'dim', text: nameOf(s.owner_email) + ' (' + s.owner_email + ') wants to share' }),
    el('h3', { text: s.title, style: 'margin-top:6px' }),
    el('div', { class: 'row', style: 'margin:8px 0 14px' }, el('span', { class: 'pill', text: s.item_count + ' photos' }), accessPill(s)),
    el('div', { class: 'row' },
      el('button', { class: 'btn green', text: 'Accept', onclick: () => respond(s.id, true) }),
      el('button', { class: 'btn ghost', text: 'Decline', onclick: () => respond(s.id, false) })));
}

function albumCard(s) {
  return el('div', { class: 'glass card', onclick: () => openAlbum(s) },
    el('h3', { text: s.title }),
    el('div', { class: 'dim', text: new Date(s.created_at).toLocaleString() }),
    el('div', { class: 'row', style: 'margin-top:10px' }, el('span', { class: 'pill', text: s.item_count + ' photos' }), accessPill(s)));
}

async function openAlbum(s) {
  album = { share: s, paths: null }; render();
  try {
    const r = await api('/rest/v1/share_items?share_id=eq.' + s.id + '&select=storage_path&order=position.asc');
    album.paths = r.ok ? (await r.json()).map((x) => x.storage_path) : [];
  } catch (e) { album.paths = []; }
  render();
}

function albumView() {
  const { share, paths } = album;
  const top = el('div', { class: 'row', style: 'margin-bottom:6px' },
    el('button', { class: 'btn ghost', text: 'Back', onclick: () => { album = null; render(); } }),
    el('h2', { text: share.title, style: 'margin:0 8px;flex:1' }));
  if (paths && paths.length && share.allow_download) {
    const b = el('button', { class: 'btn', text: 'Download all (ZIP)' });
    b.onclick = () => downloadAll(b); top.append(b);
  }
  const box = el('div', {}, top,
    el('div', { class: 'dim', text: 'From ' + nameOf(share.owner_email) + '. ' + (share.allow_download ? 'You can download these photos.' : 'View only: the sender did not allow downloads.') }));
  if (!paths) return box.append(el('div', { class: 'empty', text: 'Loading...' })), box;
  if (!paths.length) return box.append(el('div', { class: 'empty', text: 'This album is no longer available.' })), box;
  const grid = el('div', { class: 'photos' });
  const io = new IntersectionObserver((entries) => {
    for (const en of entries) {
      if (!en.isIntersecting) continue;
      io.unobserve(en.target);
      const img = en.target.querySelector('img');
      thumbUrl(en.target.dataset.path).then((u) => { img.src = u; img.onload = () => img.classList.add('in'); }).catch(() => {});
    }
  }, { rootMargin: '300px' });
  paths.forEach((p, i) => {
    const t = el('div', { class: 'ph', 'data-path': p, onclick: () => openLb(i) }, el('img', { alt: '' }));
    if (share.allow_download) t.append(el('button', { class: 'dl', title: 'Download', text: '\u2193', onclick: (e) => { e.stopPropagation(); saveFile(p, safe(share.title) + '-' + (i + 1) + '.jpg'); } }));
    grid.append(t); io.observe(t);
  });
  box.append(grid);
  return box;
}

function listView() {
  const reqs = incoming().filter((s) => s.status === 'pending');
  const acc = incoming().filter((s) => s.status === 'accepted');
  const tabs = el('div', { class: 'glass tabs' },
    el('button', { class: tab === 'shared' ? 'on' : '', text: 'Shared with me', onclick: () => { tab = 'shared'; render(); } }),
    el('button', { class: tab === 'req' ? 'on' : '', onclick: () => { tab = 'req'; render(); } }, 'Requests', reqs.length ? el('span', { class: 'badge', text: reqs.length }) : null));
  const box = el('div', {}, tabs);
  if (loading && !shares.length) return box.append(el('div', { class: 'empty', text: 'Loading...' })), box;
  if (tab === 'req') {
    if (!reqs.length) box.append(el('div', { class: 'empty', text: 'No requests right now.' }));
    else box.append(el('div', { class: 'grid' }, reqs.map(requestCard)));
    return box;
  }
  if (!acc.length) { box.append(el('div', { class: 'empty', text: 'Albums you accept appear here. Check Requests for new ones.' })); return box; }
  const bySender = new Map();
  for (const s of acc) { if (!bySender.has(s.owner_email)) bySender.set(s.owner_email, []); bySender.get(s.owner_email).push(s); }
  for (const [mail, list] of bySender) {
    box.append(el('div', { class: 'sender' }, el('div', { class: 'av', text: nameOf(mail).charAt(0) }), nameOf(mail), el('span', { class: 'dim', text: mail })));
    box.append(el('div', { class: 'grid' }, list.map(albumCard)));
  }
  return box;
}

function render() {
  app.replaceChildren(header(), !session ? loginView() : album ? albumView() : listView());
}

render();
if (session) loadShares();
