(() => {
  'use strict';

  const SB = 'https://qixnxntmaeeeyetwsgdy.supabase.co';
  const KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFpeG54bnRtYWVlZXlldHdzZ2R5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyNzE0ODEsImV4cCI6MjEwODg0NzQ4MX0.FIAPEiucXRikt9PdNtgUc5wCO1TMaCaUTkUfaKbHCeg'; // public project key (safe to publish; data is protected by login + database rules)
  const C = window.EvoraCrypto;
  const $ = (s, r) => (r || document).querySelector(s);

  function el(tag, props, ...kids) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
      if (v == null || v === false) continue;
      if (k === 'class') e.className = v;
      else if (k === 'text') e.textContent = v;
      else if (k === 'value') e.value = v;
      else if (k === 'checked') e.checked = true;
      else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
      else e.setAttribute(k, v === true ? '' : v);
    }
    for (const c of kids.flat()) if (c != null && c !== false) e.append(c.nodeType ? c : document.createTextNode(c));
    return e;
  }
  function toast(msg) {
    const t = $('#toast');
    t.textContent = msg; t.style.display = 'block';
    clearTimeout(toast.t); toast.t = setTimeout(() => { t.style.display = 'none'; }, 3500);
  }
  const nameOf = (email) => { const u = (email || '').split('@')[0] || '?'; return u.charAt(0).toUpperCase() + u.slice(1); };
  const safe = (s) => (s || 'photos').replace(/[^\w\- ]+/g, '_');
  const isEmail = (s) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s);

  // ---------------------------------------------------------------- session
  let session = null;
  try { session = JSON.parse(localStorage.getItem('evora_session') || 'null'); } catch (e) { session = null; }
  function save(s) {
    session = s;
    if (s) localStorage.setItem('evora_session', JSON.stringify(s)); else localStorage.removeItem('evora_session');
  }
  async function auth(path, body) {
    const r = await fetch(SB + '/auth/v1/' + path, { method: 'POST', headers: { apikey: KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.msg || j.error_description || j.message || 'Error ' + r.status);
    return j;
  }
  function setSession(j) {
    if (!j.access_token) throw new Error('Account created. Check your email and confirm it, then sign in.');
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
  const J = { 'Content-Type': 'application/json' };
  async function errOf(r, fallback) { try { return (await r.json()).message || fallback; } catch (e) { return fallback; } }
  async function rpc(name, body) {
    const r = await api('/rest/v1/rpc/' + name, { method: 'POST', headers: J, body: JSON.stringify(body) });
    if (!r.ok) throw new Error(await errOf(r, 'Request failed'));
    return r.json();
  }
  async function publicKeyOf(email) {
    const e = email.toLowerCase();
    try { const v = await rpc('public_key_of', { p_email: e }); return v || null; }
    catch (x) { // older database setup: read the key directly
      const r = await api('/rest/v1/public_keys?email=eq.' + encodeURIComponent(e) + '&select=public_key');
      const rows = r.ok ? await r.json() : [];
      return rows.length ? rows[0].public_key : null;
    }
  }
  async function signOut() {
    const s = session;
    save(null); shares = []; album = null; privKey = null; hasBackup = null; shareKeyCache.clear(); clearBlobs();
    $('#loginSlot').replaceChildren();
    render();
    if (s) { // revoke the session on the server too
      try { await fetch(SB + '/auth/v1/logout', { method: 'POST', headers: { apikey: KEY, Authorization: 'Bearer ' + s.access } }); } catch (e) { /* ignore */ }
    }
  }

  // ---------------------------------------------------------------- data
  let shares = [], tab = 'shared', album = null, loading = false;
  const incoming = () => shares.filter((s) => s.owner_id !== session.uid);
  const outgoing = () => shares.filter((s) => s.owner_id === session.uid);
  async function loadShares() {
    loading = true; render();
    try {
      const r = await api('/rest/v1/shares?select=*&order=created_at.desc');
      if (!r.ok) throw new Error(await errOf(r, 'Could not load shares'));
      shares = await r.json();
    } catch (e) { toast(e.message); }
    loading = false; render();
  }
  async function respond(id, accept) {
    try { await rpc('respond_share', { p_share_id: id, p_accept: accept }); toast(accept ? 'Accepted. You can now view the photos.' : 'Declined.'); }
    catch (e) { toast(e.message); }
    await loadShares();
  }
  function knownPeople() {
    let saved = [];
    try { saved = JSON.parse(localStorage.getItem('evora_people') || '[]'); } catch (e) { saved = []; }
    const fromShares = shares.map((s) => (s.owner_id === session.uid ? s.recipient_email : s.owner_email));
    return [...new Set([...saved, ...fromShares].filter(Boolean).map((e) => e.toLowerCase()))];
  }
  function rememberPerson(email) {
    let saved = [];
    try { saved = JSON.parse(localStorage.getItem('evora_people') || '[]'); } catch (e) { saved = []; }
    if (!saved.includes(email)) { saved.push(email); localStorage.setItem('evora_people', JSON.stringify(saved)); }
  }

  // ---------------------------------------------------------------- end-to-end encryption
  let privKey = null, hasBackup = null;
  const shareKeyCache = new Map();
  async function checkBackup() {
    if (hasBackup !== null) return hasBackup;
    const r = await api('/rest/v1/key_backups?select=user_id');
    hasBackup = r.ok ? (await r.json()).length > 0 : false;
    return hasBackup;
  }
  async function unlock(passcode) {
    const r = await api('/rest/v1/key_backups?select=wrapped_private,salt');
    const rows = r.ok ? await r.json() : [];
    if (!rows.length) throw new Error('No encryption key found. Turn on private sharing first.');
    let priv;
    try { priv = await C.unwrapPrivate(passcode, rows[0].salt, rows[0].wrapped_private); }
    catch (e) { throw new Error('Wrong passcode.'); }
    privKey = await C.importPrivate(priv);
  }
  async function setupEncryption(passcode) {
    const kp = await C.newKeyPair();
    const w = await C.wrapPrivate(kp.priv, passcode);
    const hdr = { ...J, Prefer: 'resolution=merge-duplicates' };
    let r = await api('/rest/v1/public_keys?on_conflict=user_id', { method: 'POST', headers: hdr, body: JSON.stringify({ email: session.email, public_key: C.b64e(kp.pub) }) });
    if (!r.ok) throw new Error(await errOf(r, 'Could not save your key'));
    r = await api('/rest/v1/key_backups?on_conflict=user_id', { method: 'POST', headers: hdr, body: JSON.stringify({ wrapped_private: w.wrapped, salt: w.salt }) });
    if (!r.ok) throw new Error(await errOf(r, 'Could not save your key backup'));
    privKey = await C.importPrivate(kp.priv);
    hasBackup = true;
  }
  async function shareAesKey(share) {
    if (shareKeyCache.has(share.id)) return shareKeyCache.get(share.id);
    if (!privKey) throw new Error('locked');
    const q = encodeURIComponent(session.email);
    const r = await api('/rest/v1/share_keys?share_id=eq.' + share.id + '&recipient_email=eq.' + q + '&select=eph_public,wrapped_key');
    const rows = r.ok ? await r.json() : [];
    if (!rows.length) throw new Error('No key for this share');
    const k = await C.unwrapShareKey(privKey, rows[0].eph_public, rows[0].wrapped_key);
    shareKeyCache.set(share.id, k);
    return k;
  }

  // dialogs
  let dlgDone = null;
  function dialog(content, onDone) {
    closeDialog();
    dlgDone = onDone || null;
    document.body.append(el('div', { class: 'modal', id: 'dlg', onclick: (e) => { if (e.target.id === 'dlg') closeDialog(); } },
      el('div', { class: 'glass modal-card' }, ...content)));
  }
  function closeDialog() {
    const d = $('#dlg'); if (d) d.remove();
    const f = dlgDone; dlgDone = null; if (f) f();
  }
  async function encDialog() {
    const has = await checkBackup();
    return new Promise((resolve) => {
      const pass = el('input', { type: 'password', placeholder: 'Encryption passcode', autocomplete: 'off' });
      const again = has ? null : el('input', { type: 'password', placeholder: 'Repeat passcode', autocomplete: 'off' });
      const err = el('div', { class: 'err' });
      const go = el('button', { class: 'btn', text: has ? 'Unlock' : 'Turn on' });
      async function run() {
        err.textContent = '';
        if (pass.value.length < 8) { err.textContent = 'Use at least 8 characters.'; return; }
        if (!has && pass.value !== again.value) { err.textContent = 'The passcodes do not match.'; return; }
        go.disabled = true; go.textContent = 'Please wait...';
        try { if (has) await unlock(pass.value); else await setupEncryption(pass.value); closeDialog(); toast('Private sharing is on.'); render(); }
        catch (e) { err.textContent = e.message; go.disabled = false; go.textContent = has ? 'Unlock' : 'Turn on'; }
      }
      go.onclick = run;
      pass.addEventListener('keydown', (e) => { if (e.key === 'Enter') run(); });
      dialog([
        el('h2', { text: has ? 'Unlock private sharing' : 'Turn on private sharing' }),
        el('p', { class: 'dim', text: has
          ? 'Enter your encryption passcode to open private photos. It never leaves this page.'
          : 'Photos are locked in your browser and only the receiver can open them, not even the server. Choose an encryption passcode (at least 8 characters). If you forget it, private photos cannot be recovered.' }),
        pass, again, err,
        el('div', { class: 'row mt' }, go, el('button', { class: 'btn ghost', text: 'Not now', onclick: () => closeDialog() })),
      ], () => resolve(!!privKey));
      pass.focus();
    });
  }

  // ---------------------------------------------------------------- photos
  const blobCache = new Map();
  const thumbOf = (p) => p.replace(/\/(\d+)\.jpg$/, '/t$1.jpg');
  function clearBlobs() { for (const p of blobCache.values()) p.then((u) => URL.revokeObjectURL(u)).catch(() => {}); blobCache.clear(); }
  async function plainBlob(path, share) {
    const r = await api('/storage/v1/object/authenticated/shared/' + path);
    if (!r.ok) throw new Error('missing');
    let buf = new Uint8Array(await r.arrayBuffer());
    if (share.encrypted) buf = await C.open(await shareAesKey(share), buf);
    return new Blob([buf], { type: 'image/jpeg' });
  }
  function fetchBlobUrl(path, share) {
    const ck = share.id + '|' + path;
    if (!blobCache.has(ck)) {
      blobCache.set(ck, plainBlob(path, share).then((b) => URL.createObjectURL(b)).catch((e) => { blobCache.delete(ck); throw e; }));
    }
    return blobCache.get(ck);
  }
  async function thumbUrl(path, share) { try { return await fetchBlobUrl(thumbOf(path), share); } catch (e) { return fetchBlobUrl(path, share); } }
  function triggerDownload(blob, name) {
    const url = URL.createObjectURL(blob);
    const a = el('a', { href: url, download: name });
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 8000);
  }
  async function saveFile(path, name, share) {
    try { triggerDownload(await plainBlob(path, share), name); } catch (e) { toast('Could not download this photo'); }
  }
  async function downloadAll(btn) {
    const { share, paths } = album;
    const old = btn.textContent; btn.disabled = true;
    try {
      const zip = new window.JSZip();
      for (let i = 0; i < paths.length; i++) {
        btn.textContent = 'Preparing ' + (i + 1) + ' / ' + paths.length;
        try { zip.file(safe(share.title) + '-' + (i + 1) + '.jpg', await plainBlob(paths[i], share)); } catch (e) { /* skip */ }
      }
      btn.textContent = 'Creating ZIP...';
      triggerDownload(await zip.generateAsync({ type: 'blob', compression: 'STORE' }), safe(share.title) + '.zip');
    } catch (e) { toast('Could not create the ZIP. Try single photos.'); }
    btn.textContent = old; btn.disabled = false;
  }

  // lightbox
  let lbIndex = 0;
  async function openLb(i) {
    lbIndex = (i + album.paths.length) % album.paths.length;
    $('#lb').classList.add('on');
    $('#lbCount').textContent = (lbIndex + 1) + ' / ' + album.paths.length;
    $('#lbDl').style.display = album.share.allow_download && album.share.owner_id !== session.uid ? '' : 'none';
    const img = $('#lbImg'); img.removeAttribute('src');
    const idx = lbIndex;
    try { const u = await fetchBlobUrl(album.paths[idx], album.share); if (idx === lbIndex) img.src = u; } catch (e) { toast('Could not open this photo'); }
  }
  $('#lbClose').onclick = () => $('#lb').classList.remove('on');
  $('#lbPrev').onclick = () => openLb(lbIndex - 1);
  $('#lbNext').onclick = () => openLb(lbIndex + 1);
  $('#lbDl').onclick = () => saveFile(album.paths[lbIndex], safe(album.share.title) + '-' + (lbIndex + 1) + '.jpg', album.share);
  document.addEventListener('keydown', (e) => {
    if (!$('#lb').classList.contains('on')) return;
    if (e.key === 'Escape') $('#lb').classList.remove('on');
    if (e.key === 'ArrowLeft') openLb(lbIndex - 1);
    if (e.key === 'ArrowRight') openLb(lbIndex + 1);
  });

  // ---------------------------------------------------------------- sending photos
  async function toJpeg(file, maxSide, quality) {
    const bmp = await createImageBitmap(file, { imageOrientation: 'from-image' });
    const scale = Math.min(1, maxSide / Math.max(bmp.width, bmp.height));
    const w = Math.max(1, Math.round(bmp.width * scale)), h = Math.max(1, Math.round(bmp.height * scale));
    const canvas = document.createElement('canvas'); canvas.width = w; canvas.height = h;
    canvas.getContext('2d').drawImage(bmp, 0, 0, w, h);
    if (bmp.close) bmp.close();
    const blob = await new Promise((res) => canvas.toBlob(res, 'image/jpeg', quality));
    if (!blob) throw new Error('encode failed');
    return new Uint8Array(await blob.arrayBuffer()); // re-encoding also removes GPS and camera data
  }

  async function createShare(o, onProgress) {
    let r = await api('/rest/v1/shares', { method: 'POST', headers: { ...J, Prefer: 'return=representation' },
      body: JSON.stringify({ owner_email: session.email, recipient_email: o.to, title: o.title, allow_download: o.allow,
        item_count: o.files.length, status: 'uploading', encrypted: o.encrypt }) });
    if (!r.ok) throw new Error(await errOf(r, 'Could not start the share'));
    const shareId = (await r.json())[0].id;
    const uploaded = [];
    try {
      const fullPx = o.allow ? 2048 : 1280, fullQ = o.allow ? 0.88 : 0.75;
      const photoKey = o.encrypt ? C.rand(32) : null;
      const encKey = o.encrypt ? await C.photoEncryptKey(photoKey) : null;
      const rows = new Array(o.files.length).fill(null);
      let next = 0, done = 0, failure = null, skipped = 0;
      const put = async (path, bytes) => {
        const res = await api('/storage/v1/object/shared/' + path, { method: 'POST', headers: { 'Content-Type': 'image/jpeg' }, body: bytes });
        if (!res.ok) throw new Error(await errOf(res, 'Upload failed'));
        uploaded.push(path);
      };
      async function worker() {
        while (!failure) {
          const i = next++;
          if (i >= o.files.length) return;
          try {
            let full, small;
            try { full = await toJpeg(o.files[i], fullPx, fullQ); small = await toJpeg(o.files[i], 480, 0.72); }
            catch (e) { skipped++; onProgress(++done, o.files.length); continue; }
            if (encKey) { full = await C.seal(encKey, full); small = await C.seal(encKey, small); }
            const base = session.uid + '/' + shareId + '/';
            await put(base + i + '.jpg', full);
            await put(base + 't' + i + '.jpg', small);
            rows[i] = { share_id: shareId, storage_path: base + i + '.jpg', position: i };
            onProgress(++done, o.files.length);
          } catch (e) { failure = e; }
        }
      }
      await Promise.all([worker(), worker(), worker()]);
      if (failure) throw failure;
      const items = rows.filter(Boolean);
      if (!items.length) throw new Error('None of the files could be read as photos.');
      r = await api('/rest/v1/share_items', { method: 'POST', headers: J, body: JSON.stringify(items) });
      if (!r.ok) throw new Error(await errOf(r, 'Could not save the photo list'));
      if (o.encrypt) {
        const mine = await publicKeyOf(session.email);
        const targets = {}; targets[o.to] = o.recipPub; if (mine) targets[session.email] = mine;
        const keyRows = [];
        for (const [email, pub] of Object.entries(targets)) {
          const w = await C.wrapFor(photoKey, pub);
          keyRows.push({ share_id: shareId, recipient_email: email, eph_public: w.eph, wrapped_key: w.wrapped });
        }
        r = await api('/rest/v1/share_keys', { method: 'POST', headers: J, body: JSON.stringify(keyRows) });
        if (!r.ok) throw new Error(await errOf(r, 'Could not save the encryption keys'));
      }
      r = await api('/rest/v1/shares?id=eq.' + shareId, { method: 'PATCH', headers: J, body: JSON.stringify({ status: 'pending', item_count: items.length }) });
      if (!r.ok) throw new Error(await errOf(r, 'Could not finish the share'));
      return skipped;
    } catch (e) {
      try {
        if (uploaded.length) await api('/storage/v1/object/shared', { method: 'DELETE', headers: J, body: JSON.stringify({ prefixes: uploaded }) });
        await api('/rest/v1/shares?id=eq.' + shareId, { method: 'DELETE' });
      } catch (x) { /* best effort */ }
      throw e;
    }
  }

  async function stopSharing(s) {
    if (!confirm('Stop sharing "' + s.title + '"? The photos are deleted from the server and ' + s.recipient_email + ' loses access.')) return;
    try {
      const r = await api('/rest/v1/share_items?share_id=eq.' + s.id + '&select=storage_path');
      if (r.ok) {
        const paths = (await r.json()).map((x) => x.storage_path);
        const all = paths.concat(paths.map(thumbOf));
        if (all.length) await api('/storage/v1/object/shared', { method: 'DELETE', headers: J, body: JSON.stringify({ prefixes: all }) });
      }
      const d = await api('/rest/v1/shares?id=eq.' + s.id, { method: 'DELETE' });
      if (!d.ok) throw new Error('Could not delete the share');
      toast('Stopped sharing.');
    } catch (e) { toast(e.message); }
    await loadShares();
  }

  // ---------------------------------------------------------------- views
  function loginView() {
    let create = false;
    const email = el('input', { type: 'email', placeholder: 'Email', autocomplete: 'username' });
    const pass = el('input', { type: 'password', placeholder: 'Password (at least 8 characters)', autocomplete: 'current-password' });
    const err = el('div', { class: 'err' });
    const go = el('button', { class: 'btn mt', text: 'Sign in' });
    const sw = el('button', { class: 'btn ghost mt', text: 'Create a new account' });
    async function submit() {
      err.textContent = ''; go.disabled = true;
      try {
        const body = { email: email.value.trim().toLowerCase(), password: pass.value };
        if (create && body.password.length < 8) throw new Error('Use a password of at least 8 characters.');
        setSession(await auth(create ? 'signup' : 'token?grant_type=password', body));
        await loadShares();
      } catch (e) { err.textContent = e.message; }
      go.disabled = false;
    }
    go.onclick = submit;
    pass.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
    sw.onclick = () => {
      create = !create;
      go.textContent = create ? 'Create account' : 'Sign in';
      sw.textContent = create ? 'I already have an account' : 'Create a new account';
      pass.setAttribute('autocomplete', create ? 'new-password' : 'current-password');
    };
    return el('div', { class: 'glass login' },
      el('h2', { text: 'Sign in to Evora' }),
      el('div', { class: 'dim', text: 'Use the same email and password as in the Evora app. You see photos only after you accept them.' }),
      email, pass, err, go, sw);
  }

  function header() {
    return el('header', { class: 'appbar' },
      el('img', { src: '/icon-192.png', width: '40', height: '40', alt: 'Evora logo' }),
      el('h1', { text: 'Evora' }),
      el('span', { class: 'dim', text: session.email }),
      el('button', { class: 'btn ghost small', text: 'Refresh', onclick: loadShares }),
      el('button', { class: 'btn ghost small', text: 'Sign out', onclick: signOut }));
  }

  function encBar() {
    if (privKey) return el('div', { class: 'enc ok', text: 'Private sharing is unlocked on this page.' });
    return el('div', { class: 'enc' },
      el('span', { text: 'End-to-end encrypted photos need your encryption passcode.' }),
      el('button', { class: 'btn ghost small', text: 'Unlock or turn on', onclick: () => encDialog() }));
  }

  function accessPills(s) {
    return el('span', {},
      el('span', { class: 'pill' + (s.allow_download ? ' ok' : ''), text: s.allow_download ? 'Download allowed' : 'View only' }),
      s.encrypted ? el('span', { class: 'pill ok', text: ' Encrypted' }) : null);
  }

  function requestCard(s) {
    return el('div', { class: 'glass card' },
      el('div', { class: 'dim', text: nameOf(s.owner_email) + ' (' + s.owner_email + ') wants to share' }),
      el('h3', { text: s.title }),
      el('div', { class: 'row' }, el('span', { class: 'pill', text: s.item_count + ' photos' }), accessPills(s)),
      el('div', { class: 'row mt' },
        el('button', { class: 'btn green', text: 'Accept', onclick: () => respond(s.id, true) }),
        el('button', { class: 'btn ghost', text: 'Decline', onclick: () => respond(s.id, false) })));
  }

  function albumCard(s) {
    return el('div', { class: 'glass card click', onclick: () => openAlbum(s) },
      el('h3', { text: s.title }),
      el('div', { class: 'dim', text: new Date(s.created_at).toLocaleString() }),
      el('div', { class: 'row mt' }, el('span', { class: 'pill', text: s.item_count + ' photos' }), accessPills(s)));
  }

  async function openAlbum(s) {
    album = { share: s, paths: null }; render();
    try {
      const r = await api('/rest/v1/share_items?share_id=eq.' + s.id + '&select=storage_path&order=position.asc');
      album.paths = r.ok ? (await r.json()).map((x) => x.storage_path) : [];
    } catch (e) { album.paths = []; }
    render();
  }

  function unlockBox() {
    const pass = el('input', { type: 'password', placeholder: 'Encryption passcode' });
    const err = el('div', { class: 'err' });
    const go = el('button', { class: 'btn mt', text: 'Unlock' });
    async function run() {
      err.textContent = ''; go.disabled = true; go.textContent = 'Unlocking...';
      try { await unlock(pass.value); render(); }
      catch (e) { err.textContent = e.message; go.disabled = false; go.textContent = 'Unlock'; }
    }
    go.onclick = run;
    pass.addEventListener('keydown', (e) => { if (e.key === 'Enter') run(); });
    return el('div', { class: 'glass login mt' },
      el('h2', { text: 'Private photos' }),
      el('div', { class: 'dim', text: 'These photos are end-to-end encrypted. Enter the encryption passcode you set in Evora. It never leaves this page.' }),
      pass, err, go);
  }

  function albumView() {
    const { share, paths } = album;
    const mine = share.owner_id === session.uid;
    const canSave = share.allow_download && !mine;
    const top = el('div', { class: 'row' },
      el('button', { class: 'btn ghost', text: 'Back', onclick: () => { album = null; render(); } }),
      el('h2', { text: share.title }), el('span', { class: 'flex1' }));
    if (paths && paths.length && canSave && window.JSZip) {
      const b = el('button', { class: 'btn', text: 'Download all (ZIP)' });
      b.onclick = () => downloadAll(b); top.append(b);
    }
    const note = mine ? 'Shared with ' + share.recipient_email + '.'
      : 'From ' + nameOf(share.owner_email) + '. ' + (share.allow_download ? 'You can download these photos.' : 'View only: the sender did not allow downloads.');
    const box = el('div', {}, top, el('div', { class: 'dim', text: note }));
    if (!paths) { box.append(el('div', { class: 'empty', text: 'Loading...' })); return box; }
    if (!paths.length) { box.append(el('div', { class: 'empty', text: 'This album is no longer available.' })); return box; }
    if (share.encrypted && !privKey) { box.append(unlockBox()); return box; }
    const grid = el('div', { class: 'photos' });
    const io = new IntersectionObserver((entries) => {
      for (const en of entries) {
        if (!en.isIntersecting) continue;
        io.unobserve(en.target);
        const img = en.target.querySelector('img');
        thumbUrl(en.target.dataset.path, share).then((u) => { img.onload = () => img.classList.add('in'); img.src = u; }).catch(() => {});
      }
    }, { rootMargin: '300px' });
    paths.forEach((p, i) => {
      const t = el('div', { class: 'ph', 'data-path': p, onclick: () => openLb(i) }, el('img', { alt: '' }));
      if (canSave) t.append(el('button', { class: 'dl', title: 'Download', text: '\u2193',
        onclick: (e) => { e.stopPropagation(); saveFile(p, safe(share.title) + '-' + (i + 1) + '.jpg', share); } }));
      grid.append(t); io.observe(t);
    });
    box.append(grid);
    return box;
  }

  function statusPill(s) {
    const m = { uploading: ['Uploading', ''], pending: ['Waiting for accept', 'warn'], accepted: ['Accepted', 'ok'], rejected: ['Declined', 'bad'] }[s.status] || [s.status, ''];
    return el('span', { class: 'pill ' + m[1], text: m[0] });
  }

  function sentView() {
    const list = outgoing();
    if (!list.length) return el('div', { class: 'empty', text: 'Nothing sent yet. Use "Send photos" to share your first photos.' });
    return el('div', { class: 'grid' }, list.map((s) => el('div', { class: 'glass card' },
      el('h3', { text: s.title }),
      el('div', { class: 'dim', text: 'To ' + s.recipient_email + '  ' + new Date(s.created_at).toLocaleDateString() }),
      el('div', { class: 'row mt' }, statusPill(s), el('span', { class: 'pill', text: s.item_count + ' photos' }), s.encrypted ? el('span', { class: 'pill ok', text: 'Encrypted' }) : null),
      el('div', { class: 'row mt' },
        s.status === 'uploading' ? null : el('button', { class: 'btn ghost small', text: 'Open', onclick: () => openAlbum(s) }),
        el('button', { class: 'btn red small', text: 'Stop sharing', onclick: () => stopSharing(s) })))));
  }

  const F = { to: '', title: 'Photos', allow: false, secure: true, files: [] };
  function sendView() {
    const to = el('input', { type: 'email', placeholder: "Receiver's email", list: 'people', value: F.to, autocomplete: 'off' });
    to.addEventListener('input', () => { F.to = to.value; });
    const people = el('datalist', { id: 'people' }, knownPeople().map((e) => el('option', { value: e })));
    const title = el('input', { type: 'text', placeholder: 'Share name', value: F.title });
    title.addEventListener('input', () => { F.title = title.value; });
    const allow = el('input', { type: 'checkbox', checked: F.allow });
    allow.addEventListener('change', () => { F.allow = allow.checked; });
    const secure = el('input', { type: 'checkbox', checked: F.secure });
    secure.addEventListener('change', async () => {
      F.secure = secure.checked;
      if (F.secure && !privKey) { const ok = await encDialog(); if (!ok) { F.secure = false; secure.checked = false; } }
    });
    const pick = el('input', { type: 'file', accept: 'image/*', multiple: true, class: 'hidden' });
    const previews = el('div', { class: 'previews' });
    const info = el('div', { class: 'dim mt', text: F.files.length ? F.files.length + ' photos selected' : 'No photos selected' });
    function showFiles() {
      info.textContent = F.files.length ? F.files.length + ' photos selected' : 'No photos selected';
      previews.replaceChildren(...F.files.slice(0, 10).map((f) => el('img', { src: URL.createObjectURL(f), alt: '' })));
    }
    pick.addEventListener('change', () => { F.files = Array.from(pick.files); showFiles(); });
    showFiles();
    const bar = el('div', { class: 'bar' });
    const prog = el('div', { class: 'progress hidden' }, bar);
    const msg = el('div', { class: 'dim mt' });
    const send = el('button', { class: 'btn', text: 'Review and send' });
    send.onclick = async () => {
      const t = F.to.trim().toLowerCase(), name = F.title.trim();
      if (!isEmail(t)) return toast("Enter the receiver's email address.");
      if (t === session.email) return toast('Use a different email than your own.');
      if (!name) return toast('Give this share a name.');
      if (!F.files.length) return toast('Choose some photos first.');
      let encrypt = F.secure, recipPub = null;
      if (encrypt) {
        if (!privKey && !(await encDialog())) return;
        recipPub = await publicKeyOf(t).catch(() => null);
        if (!recipPub) {
          if (!confirm(t + ' has not turned on private sharing, so these photos cannot be end-to-end encrypted for them. Send without encryption?')) return;
          encrypt = false;
        }
      }
      if (!confirm('Send ' + F.files.length + ' photos to ' + t + '?\nAccess: ' + (F.allow ? 'view and download' : 'view only') +
        '\nEncryption: ' + (encrypt ? 'end-to-end' : 'none') + '\n\nThey see nothing until they accept.')) return;
      send.disabled = true; prog.classList.remove('hidden'); msg.textContent = 'Uploading... keep this page open.';
      try {
        const skipped = await createShare({ to: t, title: name, allow: F.allow, files: F.files, encrypt, recipPub },
          (d, n) => { bar.style.width = Math.round((d / n) * 100) + '%'; msg.textContent = 'Uploading ' + d + ' of ' + n + '... keep this page open.'; });
        rememberPerson(t);
        F.files = []; F.title = 'Photos';
        toast('Sent to ' + t + '. Waiting for them to accept.' + (skipped ? ' ' + skipped + ' files were not photos and were skipped.' : ''));
        tab = 'sent'; await loadShares();
      } catch (e) { msg.textContent = e.message; send.disabled = false; }
    };
    return el('div', { class: 'glass form' },
      el('h2', { text: 'Send photos' }),
      el('div', { class: 'dim', text: 'Choose photos from this computer. They are resized and stripped of location data before upload.' }),
      to, people, title,
      el('label', { class: 'chk' }, secure, el('span', {}, el('strong', { text: 'End-to-end encrypted' }), el('br'), el('span', { class: 'dim', text: 'Only the receiver can open these photos.' }))),
      el('label', { class: 'chk' }, allow, el('span', {}, el('strong', { text: 'Allow download' }), el('br'), el('span', { class: 'dim', text: 'Off: view only, with a lower-quality copy.' }))),
      el('div', { class: 'row mt' }, el('button', { class: 'btn ghost', text: 'Choose photos', onclick: () => pick.click() }), pick),
      info, previews, prog, msg, el('div', { class: 'mt' }, send));
  }

  function mainView() {
    const reqs = incoming().filter((s) => s.status === 'pending');
    const acc = incoming().filter((s) => s.status === 'accepted');
    const mk = (id, label, badge) => el('button', { class: tab === id ? 'on' : '', onclick: () => { tab = id; render(); } }, label, badge ? el('span', { class: 'badge', text: badge }) : null);
    const tabs = el('div', { class: 'glass tabs' }, mk('shared', 'Shared with me'), mk('req', 'Requests', reqs.length || ''), mk('sent', 'Sent'), mk('send', 'Send photos'));
    const box = el('div', {}, encBar(), tabs);
    if (loading && !shares.length) { box.append(el('div', { class: 'empty', text: 'Loading...' })); return box; }
    if (tab === 'req') {
      box.append(reqs.length ? el('div', { class: 'grid' }, reqs.map(requestCard)) : el('div', { class: 'empty', text: 'No requests right now.' }));
    } else if (tab === 'sent') {
      box.append(sentView());
    } else if (tab === 'send') {
      box.append(sendView());
    } else if (!acc.length) {
      box.append(el('div', { class: 'empty', text: 'Albums you accept appear here. Check Requests for new ones.' }));
    } else {
      const by = new Map();
      for (const s of acc) { if (!by.has(s.owner_email)) by.set(s.owner_email, []); by.get(s.owner_email).push(s); }
      for (const [mail, list] of by) {
        box.append(el('div', { class: 'sender' }, el('div', { class: 'av', text: nameOf(mail).charAt(0) }), nameOf(mail), el('span', { class: 'dim', text: mail })));
        box.append(el('div', { class: 'grid' }, list.map(albumCard)));
      }
    }
    return box;
  }

  function render() {
    const landing = $('#landing'), app = $('#app');
    if (!session) {
      landing.hidden = false; app.hidden = true;
      const slot = $('#loginSlot');
      if (!slot.firstChild) slot.append(loginView());
      return;
    }
    landing.hidden = true; app.hidden = false;
    app.replaceChildren(header(), album ? albumView() : mainView());
  }

  render();
  if (session) loadShares();
})();
