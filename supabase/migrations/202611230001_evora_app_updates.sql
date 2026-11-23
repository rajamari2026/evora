-- Evora release management. Safe to run once in the Supabase SQL Editor.
-- Admin membership is granted manually by the project owner only.

create table if not exists public.app_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.app_releases (
  id uuid primary key default gen_random_uuid(),
  version_name text not null,
  version_code bigint not null unique check (version_code > 0),
  release_notes text not null default '',
  apk_url text not null,
  is_mandatory boolean not null default false,
  min_supported_version_code bigint not null default 1,
  status text not null default 'prepared'
    check (status in ('prepared', 'published', 'paused', 'withdrawn')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  published_at timestamptz
);

alter table public.app_admins enable row level security;
alter table public.app_releases enable row level security;

grant select on public.app_admins to authenticated;
grant select on public.app_releases to anon, authenticated;
grant insert, update, delete on public.app_releases to authenticated;

create or replace function public.is_evora_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.app_admins where user_id = auth.uid()
  );
$$;

revoke all on function public.is_evora_admin() from public;
grant execute on function public.is_evora_admin() to authenticated;

drop policy if exists "Admin can read own admin record" on public.app_admins;
create policy "Admin can read own admin record"
on public.app_admins for select to authenticated
using (user_id = auth.uid());

drop policy if exists "Read published releases or admin releases" on public.app_releases;
create policy "Read published releases or admin releases"
on public.app_releases for select to anon, authenticated
using (status = 'published' or (auth.uid() is not null and public.is_evora_admin()));

drop policy if exists "Only admins create releases" on public.app_releases;
create policy "Only admins create releases"
on public.app_releases for insert to authenticated
with check (public.is_evora_admin() and created_by = auth.uid());

drop policy if exists "Only admins update releases" on public.app_releases;
create policy "Only admins update releases"
on public.app_releases for update to authenticated
using (public.is_evora_admin())
with check (public.is_evora_admin());

drop policy if exists "Only admins delete releases" on public.app_releases;
create policy "Only admins delete releases"
on public.app_releases for delete to authenticated
using (public.is_evora_admin());


-- Device tokens for FCM. The Flutter registration code is enabled after the
-- Firebase project and Android google-services.json are configured.
create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  fcm_token text not null unique,
  device_label text not null default 'Android device',
  enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.user_devices enable row level security;
grant select, insert, update, delete on public.user_devices to authenticated;
drop policy if exists "Users manage their own Evora devices" on public.user_devices;
create policy "Users manage their own Evora devices"
on public.user_devices for all to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- Public download bucket: anyone with the APK URL can download; only admins
-- can upload, replace, or delete files. Use it only for public app binaries.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'evora-apk',
  'evora-apk',
  true,
  157286400,
  array['application/vnd.android.package-archive']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Evora admins upload APKs" on storage.objects;
create policy "Evora admins upload APKs"
on storage.objects for insert to authenticated
with check (bucket_id = 'evora-apk' and public.is_evora_admin());

drop policy if exists "Evora admins replace APKs" on storage.objects;
create policy "Evora admins replace APKs"
on storage.objects for update to authenticated
using (bucket_id = 'evora-apk' and public.is_evora_admin())
with check (bucket_id = 'evora-apk' and public.is_evora_admin());

drop policy if exists "Evora admins delete APKs" on storage.objects;
create policy "Evora admins delete APKs"
on storage.objects for delete to authenticated
using (bucket_id = 'evora-apk' and public.is_evora_admin());

-- After creating the first admin account, run:
-- insert into public.app_admins(user_id) values ('YOUR_AUTH_USER_UUID');
