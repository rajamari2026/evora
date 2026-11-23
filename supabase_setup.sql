-- EventRoll sharing setup. Paste ALL of this into Supabase > SQL Editor > Run.

-- 1. Tables ---------------------------------------------------------------
create table if not exists public.shares (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users on delete cascade,
  owner_email text not null,
  recipient_email text not null,
  title text not null,
  allow_download boolean not null default false,
  item_count int not null default 0,
  status text not null default 'uploading'
    check (status in ('uploading','pending','accepted','rejected')),
  created_at timestamptz not null default now()
);

create table if not exists public.share_items (
  id uuid primary key default gen_random_uuid(),
  share_id uuid not null references public.shares on delete cascade,
  storage_path text not null,
  position int not null default 0
);

alter table public.shares enable row level security;
alter table public.share_items enable row level security;

-- 2. Share rules ------------------------------------------------------------
drop policy if exists shares_select on public.shares;
create policy shares_select on public.shares for select to authenticated
  using (
    owner_id = auth.uid()
    or (lower(recipient_email) = lower(auth.jwt() ->> 'email') and status <> 'uploading')
  );

drop policy if exists shares_insert on public.shares;
create policy shares_insert on public.shares for insert to authenticated
  with check (owner_id = auth.uid() and status = 'uploading');

-- Owner may only move a share between uploading and pending.
-- (Only the receiver, through respond_share, can accept or decline.)
drop policy if exists shares_update on public.shares;
create policy shares_update on public.shares for update to authenticated
  using (owner_id = auth.uid() and status in ('uploading','pending'))
  with check (owner_id = auth.uid() and status in ('uploading','pending'));

drop policy if exists shares_delete on public.shares;
create policy shares_delete on public.shares for delete to authenticated
  using (owner_id = auth.uid());

drop policy if exists items_select on public.share_items;
create policy items_select on public.share_items for select to authenticated
  using (exists (
    select 1 from public.shares s
    where s.id = share_id
      and (s.owner_id = auth.uid()
           or (lower(s.recipient_email) = lower(auth.jwt() ->> 'email')
               and s.status = 'accepted'))
  ));

drop policy if exists items_insert on public.share_items;
create policy items_insert on public.share_items for insert to authenticated
  with check (exists (
    select 1 from public.shares s where s.id = share_id and s.owner_id = auth.uid()
  ));

drop policy if exists items_delete on public.share_items;
create policy items_delete on public.share_items for delete to authenticated
  using (exists (
    select 1 from public.shares s where s.id = share_id and s.owner_id = auth.uid()
  ));

-- 3. Receiver accepts / declines -------------------------------------------
create or replace function public.respond_share(p_share_id uuid, p_accept boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.shares
     set status = case when p_accept then 'accepted' else 'rejected' end
   where id = p_share_id
     and status in ('pending','accepted')
     and lower(recipient_email) = lower(auth.jwt() ->> 'email');
  if not found then
    raise exception 'Share not found or already answered';
  end if;
end;
$$;

revoke all on function public.respond_share(uuid, boolean) from public;
grant execute on function public.respond_share(uuid, boolean) to authenticated;

-- 4. Private photo storage ---------------------------------------------------
insert into storage.buckets (id, name, public)
values ('shared', 'shared', false)
on conflict (id) do nothing;

drop policy if exists shared_upload on storage.objects;
create policy shared_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'shared' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists shared_delete on storage.objects;
create policy shared_delete on storage.objects for delete to authenticated
  using (bucket_id = 'shared' and (storage.foldername(name))[1] = auth.uid()::text);

-- Owner can read own files. Receiver can read only after accepting.
drop policy if exists shared_read on storage.objects;
create policy shared_read on storage.objects for select to authenticated
  using (
    bucket_id = 'shared'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (
        select 1
          from public.share_items si
          join public.shares s on s.id = si.share_id
         where si.storage_path = name
           and s.status = 'accepted'
           and lower(s.recipient_email) = lower(auth.jwt() ->> 'email')
      )
    )
  );
