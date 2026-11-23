(() => {
  'use strict';
  const SB = 'https://qixnxntmaeeeyetwsgdy.supabase.co';
  const KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFpeG54bnRtYWVlZXlldHdzZ2R5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyNzE0ODEsImV4cCI6MjEwODg0NzQ4MX0.FIAPEiucXRikt9PdNtgUc5wCO1TMaCaUTkUfaKbHCeg';
  const $ = (id) => document.getElementById(id);
  let session = null;
  let authorized = false;
  try { session = JSON.parse(sessionStorage.getItem('evora_admin_session') || 'null'); } catch (_) {}

  function save(s) {
    session = s;
    if (s) sessionStorage.setItem('evora_admin_session', JSON.stringify(s));
    else sessionStorage.removeItem('evora_admin_session');
  }
  function message(id, text) { $(id).textContent = text || ''; }
  function toast(text) {
    const t = $('toast'); t.textContent = text; t.style.display = 'block';
    clearTimeout(toast.timer); toast.timer = setTimeout(() => { t.style.display = 'none'; }, 3500);
  }
  async function auth(path, body) {
    const r = await fetch(SB + '/auth/v1/' + path, {
      method: 'POST', headers: { apikey: KEY, 'Content-Type': 'application/json' }, body: JSON.stringify(body)
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j.msg || j.error_description || j.message || `Sign-in failed (${r.status})`);
    return j;
  }
  async function refreshSession() {
    if (!session?.refresh) return false;
    try {
      const j = await auth('token?grant_type=refresh_token', { refresh_token: session.refresh });
      save({ access: j.access_token, refresh: j.refresh_token, uid: j.user.id, email: j.user.email });
      return true;
    } catch (_) { save(null); return false; }
  }
  async function api(path, options = {}, retry = true) {
    const headers = { apikey: KEY, Authorization: 'Bearer ' + session.access, ...(options.headers || {}) };
    const r = await fetch(SB + path, { ...options, headers });
    if (r.status === 401 && retry && await refreshSession()) return api(path, options, false);
    if (r.status === 401) { save(null); show(); throw new Error('Your session expired. Sign in again.'); }
    return r;
  }
  async function verifyAdmin() {
    const r = await api('/rest/v1/rpc/is_evora_admin', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' });
    if (!r.ok || await r.json() !== true) throw new Error('This account is not an Evora administrator.');
  }
  function show() {
    $('login').hidden = !!session;
    $('panel').hidden = !session || !authorized;
    if (session) $('signedIn').textContent = `Signed in as ${session.email}`;
  }
  async function signIn() {
    message('loginError', '');
    try {
      const j = await auth('token?grant_type=password', { email: $('email').value.trim().toLowerCase(), password: $('password').value });
      save({ access: j.access_token, refresh: j.refresh_token, uid: j.user.id, email: j.user.email });
      await verifyAdmin(); authorized = true; show(); await loadReleases();
    } catch (e) { save(null); authorized = false; message('loginError', e.message); show(); }
  }
  async function signOut() {
    const old = session; save(null); authorized = false; show();
    if (old?.access) fetch(SB + '/auth/v1/logout', { method: 'POST', headers: { apikey: KEY, Authorization: 'Bearer ' + old.access } }).catch(() => {});
  }
  async function loadReleases() {
    $('releases').textContent = 'Loading…';
    try {
      const r = await api('/rest/v1/app_releases?select=id,version_name,version_code,release_notes,is_mandatory,status,created_at&order=version_code.desc');
      if (!r.ok) throw new Error('Could not load releases.');
      const rows = await r.json();
      const root = $('releases'); root.replaceChildren();
      if (!rows.length) { root.textContent = 'No releases yet.'; return; }
      rows.forEach((item) => {
        const wrap = document.createElement('div'); wrap.className = 'release';
        const title = document.createElement('strong'); title.textContent = `Evora ${item.version_name} · build ${item.version_code}`;
        const status = document.createElement('div'); status.className = 'status'; status.textContent = `${item.status.toUpperCase()}${item.is_mandatory ? ' · MANDATORY' : ''}`;
        const notes = document.createElement('p'); notes.className = 'dim'; notes.textContent = item.release_notes || '';
        const controls = document.createElement('div'); controls.className = 'row';
        if (item.status !== 'published') controls.append(actionButton('Publish to everyone', () => setStatus(item.id, 'published')));
        if (item.status === 'published') controls.append(actionButton('Pause', () => setStatus(item.id, 'paused'), true));
        if (item.status !== 'withdrawn') controls.append(actionButton('Withdraw', () => setStatus(item.id, 'withdrawn'), true));
        wrap.append(title, status, notes, controls); root.append(wrap);
      });
    } catch (e) { $('releases').textContent = e.message; }
  }
  function actionButton(label, action, ghost = false) {
    const b = document.createElement('button'); b.className = 'btn small' + (ghost ? ' ghost' : '');
    b.textContent = label; b.addEventListener('click', action); return b;
  }
  async function setStatus(id, status) {
    if (status === 'published' && !confirm('Publish this release to every Evora user?')) return;
    try {
      const patch = { status };
      if (status === 'published') patch.published_at = new Date().toISOString();
      const r = await api('/rest/v1/app_releases?id=eq.' + encodeURIComponent(id), {
        method: 'PATCH', headers: { 'Content-Type': 'application/json', Prefer: 'return=minimal' }, body: JSON.stringify(patch)
      });
      if (!r.ok) throw new Error(await r.text());
      if (status === 'published') {
        const push = await api('/functions/v1/notify-release', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ release_id: id })
        });
        if (!push.ok) toast('Published. In-app update checks are active; push notifications are not configured yet.');
        else {
          const result = await push.json();
          toast(result.sent > 0 ? `Published. Push notifications sent to ${result.sent} device(s).` : 'Published. No devices are registered for push yet; in-app checks remain active.');
        }
      } else {
        toast(`Release ${status}.`);
      }
      await loadReleases();
    } catch (e) { toast(e.message); }
  }
  async function prepareRelease() {
    message('prepareError', '');
    const version = $('version').value.trim();
    const code = Number($('code').value);
    const file = $('apk').files[0];
    if (!version || !Number.isSafeInteger(code) || code < 1 || !file) {
      message('prepareError', 'Enter a version name, a positive version code, and select an APK.'); return;
    }
    if (!file.name.toLowerCase().endsWith('.apk')) { message('prepareError', 'Select an APK file.'); return; }
    $('prepare').disabled = true; $('prepare').textContent = 'Uploading…';
    try {
      const safe = version.replace(/[^A-Za-z0-9._-]/g, '_');
      const objectPath = `releases/${safe}/Evora-${safe}.apk`;
      const upload = await api('/storage/v1/object/evora-apk/' + objectPath.split('/').map(encodeURIComponent).join('/'), {
        method: 'POST', headers: { 'Content-Type': 'application/vnd.android.package-archive', 'x-upsert': 'true' }, body: file
      });
      if (!upload.ok) throw new Error('APK upload failed: ' + await upload.text());
      const apkUrl = `${SB}/storage/v1/object/public/evora-apk/${objectPath}`;
      const create = await api('/rest/v1/app_releases', {
        method: 'POST', headers: { 'Content-Type': 'application/json', Prefer: 'return=representation' },
        body: JSON.stringify({
          version_name: version, version_code: code, release_notes: $('notes').value.trim(), apk_url: apkUrl,
          is_mandatory: $('mandatory').checked, min_supported_version_code: $('mandatory').checked ? code : 1,
          status: 'prepared', created_by: session.uid
        })
      });
      if (!create.ok) throw new Error('Could not save release: ' + await create.text());
      $('version').value = ''; $('code').value = ''; $('notes').value = ''; $('apk').value = ''; $('mandatory').checked = false;
      toast('Release prepared. It has not been published to users.'); await loadReleases();
    } catch (e) { message('prepareError', e.message); }
    finally { $('prepare').disabled = false; $('prepare').textContent = 'Upload APK and prepare'; }
  }

  $('signIn').addEventListener('click', signIn);
  $('password').addEventListener('keydown', (e) => { if (e.key === 'Enter') signIn(); });
  $('signOut').addEventListener('click', signOut);
  $('prepare').addEventListener('click', prepareRelease);
  show();
  if (session) verifyAdmin().then(() => { authorized = true; show(); return loadReleases(); }).catch((e) => { save(null); authorized = false; show(); message('loginError', e.message); });
})();
