(() => {
  'use strict';
  const SB = 'https://qixnxntmaeeeyetwsgdy.supabase.co';
  const KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFpeG54bnRtYWVlZXlldHdzZ2R5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyNzE0ODEsImV4cCI6MjEwODg0NzQ4MX0.FIAPEiucXRikt9PdNtgUc5wCO1TMaCaUTkUfaKbHCeg';
  const root = document.querySelector('#admin');
  const J = { 'Content-Type': 'application/json' };

  function el(tag, props, ...kids) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
      if (v == null || v === false) continue;
      if (k === 'class') e.className = v;
      else if (k === 'text') e.textContent = v;
      else if (k === 'checked') e.checked = true;
      else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
      else e.setAttribute(k, v === true ? '' : v);
    }
    for (const c of kids.flat()) if (c != null && c !== false) e.append(c.nodeType ? c : document.createTextNode(c));
    return e;
  }
  function toast(msg) {
    const t = document.querySelector('#toast');
    t.textContent = msg; t.style.display = 'block';
    clearTimeout(toast.t); toast.t = setTimeout(() => { t.style.display = 'none'; }, 3500);
  }

  let session = null;
  try { session = JSON.parse(localStorage.getItem('evora_session') || 'null'); } catch (e) { session = null; }

  async function refresh() {
    if (!session || !session.refresh) return false;
    try {
      const r = await fetch(SB + '/auth/v1/token?grant_type=refresh_token', { method: 'POST', headers: { apikey: KEY, ...J }, body: JSON.stringify({ refresh_token: session.refresh }) });
      const j = await r.json();
      if (!r.ok || !j.access_token) return false;
      session = { access: j.access_token, refresh: j.refresh_token, email: (j.user.email || '').toLowerCase(), uid: j.user.id };
      localStorage.setItem('evora_session', JSON.stringify(session));
      return true;
    } catch (e) { return false; }
  }
  async function api(path, opts = {}, retry = true) {
    const r = await fetch(SB + path, { ...opts, headers: { apikey: KEY, Authorization: 'Bearer ' + session.access, ...(opts.headers || {}) } });
    if (r.status === 401 && retry && await refresh()) return api(path, opts, false);
    return r;
  }

  let releases = [];
  const pillClass = { published: 'ok', prepared: 'warn', withdrawn: 'bad', paused: 'bad' };

  function card(rel) {
    const notes = el('textarea', { rows: '3', class: 'notes' }, rel.release_notes || '');
    const mand = el('input', { type: 'checkbox', checked: rel.is_mandatory });
    const live = rel.status === 'published';
    const bar = el('div', { class: 'row mt' },
      el('button', { class: 'btn green small', text: live ? 'Save changes' : 'Publish to all users', onclick: () => save(rel, 'published', notes.value, mand.checked) }),
      live ? el('button', { class: 'btn ghost small', text: 'Withdraw', onclick: () => save(rel, 'withdrawn', notes.value, mand.checked) }) : null,
      el('button', { class: 'btn ghost small', text: 'Copy download link', onclick: async () => { try { await navigator.clipboard.writeText(rel.apk_url); toast('Link copied.'); } catch (e) { toast(rel.apk_url); } } }),
      el('button', { class: 'btn red small', text: 'Delete', onclick: () => remove(rel) }));
    return el('div', { class: 'glass card' },
      el('div', { class: 'row' }, el('h3', { text: 'Version ' + rel.version_name }), el('span', { class: 'pill ' + (pillClass[rel.status] || ''), text: rel.status }), el('span', { class: 'pill', text: 'build ' + rel.version_code })),
      el('div', { class: 'dim', text: 'Created ' + new Date(rel.created_at).toLocaleString() + (rel.published_at ? '  Published ' + new Date(rel.published_at).toLocaleString() : '') }),
      el('label', { class: 'dim mt' }, 'What is new (shown to users)'), notes,
      el('label', { class: 'chk' }, mand, el('span', {}, el('strong', { text: 'Mandatory' }), el('br'), el('span', { class: 'dim', text: 'Users cannot skip this update.' }))),
      bar);
  }

  async function save(rel, status, notes, mandatory) {
    const body = { status, release_notes: notes, is_mandatory: mandatory };
    if (status === 'published' && rel.status !== 'published') body.published_at = new Date().toISOString();
    const r = await api('/rest/v1/app_releases?id=eq.' + rel.id, { method: 'PATCH', headers: J, body: JSON.stringify(body) });
    toast(r.ok ? (status === 'published' ? 'Published. Users see it the next time they open Veoa.' : 'Withdrawn.') : 'Could not save. Are you an admin?');
    await load();
  }

  async function remove(rel) {
    if (!confirm('Delete version ' + rel.version_name + ' and its APK file?')) return;
    const file = (rel.apk_url || '').split('/').pop();
    if (file) await api('/storage/v1/object/evora-apk', { method: 'DELETE', headers: J, body: JSON.stringify({ prefixes: [file] }) });
    const r = await api('/rest/v1/app_releases?id=eq.' + rel.id, { method: 'DELETE' });
    toast(r.ok ? 'Deleted.' : 'Could not delete.');
    await load();
  }

  function message(title, text, link) {
    root.replaceChildren(el('div', { class: 'glass login mt' }, el('h2', { text: title }), el('p', { class: 'dim', text: text }),
      link ? el('a', { class: 'btn', href: './', text: 'Open the home page' }) : null));
  }

  async function load() {
    if (!session) return message('Sign in first', 'Open the home page, sign in with your admin account, then come back to this page.', true);
    root.replaceChildren(el('div', { class: 'empty', text: 'Loading...' }));
    const a = await api('/rest/v1/app_admins?select=user_id');
    const rows = a.ok ? await a.json() : [];
    if (!rows.length) return message('Not an admin', session.email + ' is not an app admin. Sign in with the admin account.', true);
    const r = await api('/rest/v1/app_releases?select=*&order=version_code.desc');
    releases = r.ok ? await r.json() : [];
    root.replaceChildren(
      el('header', { class: 'appbar' }, el('h1', { text: 'Veoa releases' }), el('span', { class: 'dim', text: session.email }),
        el('a', { class: 'btn ghost small', href: './', text: 'Home' }), el('button', { class: 'btn ghost small', text: 'Refresh', onclick: load })),
      el('p', { class: 'dim', text: 'Every push to GitHub builds the app and adds a prepared version here. Press Publish to send it to all users. They are asked to update the next time they open Veoa.' }),
      releases.length ? el('div', { class: 'grid' }, releases.map(card)) : el('div', { class: 'empty', text: 'No versions yet. Push to GitHub and wait for the build to finish.' }));
  }

  load();
})();
