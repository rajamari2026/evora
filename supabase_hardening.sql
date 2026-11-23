-- Evora hardening. Paste ALL of this into Supabase > SQL Editor > Run. Safe to run twice.

-- 1) Public keys: stop letting every signed-in user list everyone's email.
--    People look up ONE key at a time through a function instead.
drop policy if exists pk_read on public.public_keys;
drop policy if exists pk_read_own on public.public_keys;
create policy pk_read_own on public.public_keys for select to authenticated
  using (user_id = auth.uid());

create or replace function public.public_key_of(p_email text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select public_key from public.public_keys where lower(email) = lower(p_email) limit 1;
$$;
revoke all on function public.public_key_of(text) from public, anon;
grant execute on function public.public_key_of(text) to authenticated;

-- 2) A share may only list photos stored in its own folder: <owner>/<share>/...
--    (stops anyone pointing a share at someone else's stored files)
drop policy if exists items_insert on public.share_items;
create policy items_insert on public.share_items for insert to authenticated
  with check (exists (
    select 1 from public.shares s
     where s.id = share_id
       and s.owner_id = auth.uid()
       and storage_path like (s.owner_id::text || '/' || s.id::text || '/%')
  ));
