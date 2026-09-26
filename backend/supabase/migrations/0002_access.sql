-- 0002: privileges, RLS, storage bucket (PLAN.md §7.1, §7.2).
-- Members may only SELECT. Every write goes through app-api (service role), so there
-- are no insert/update/delete policies at all.

-- ── Privileges ────────────────────────────────────────────────────────────────
-- Supabase grants anon/authenticated everything on new objects in public by default.
-- Take that away and grant back only what is listed below. Future migrations must
-- grant explicitly too.

alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon, authenticated;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

-- Reference data: readable before sign-in (the app checks the schema version early).
grant select on public.schema_version, public.palettes, public.device_models to anon, authenticated;
grant select on public.frame, public.members, public.images, public.invites, public.quota_config to authenticated;

-- RLS helpers live in private and run as their owner, so they can read members
-- without recursing through RLS.
grant usage on schema private to authenticated;

create function private.is_member() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.members m where m.user_id = (select auth.uid()));
$$;

create function private.is_owner() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.members m where m.user_id = (select auth.uid()) and m.role = 'owner'
  );
$$;

revoke execute on all functions in schema private from public, anon;
grant execute on function private.is_member(), private.is_owner() to authenticated;

-- ── RLS ───────────────────────────────────────────────────────────────────────

alter table public.schema_version enable row level security;
alter table public.palettes       enable row level security;
alter table public.device_models  enable row level security;
alter table public.frame          enable row level security;
alter table public.members        enable row level security;
alter table public.images         enable row level security;
alter table public.invites        enable row level security;
alter table public.quota_config   enable row level security;

create policy "anyone reads schema version" on public.schema_version
  for select to anon, authenticated using (true);
create policy "anyone reads palettes" on public.palettes
  for select to anon, authenticated using (true);
create policy "anyone reads device models" on public.device_models
  for select to anon, authenticated using (true);

create policy "members read the frame" on public.frame
  for select to authenticated using (private.is_member());
create policy "members read members" on public.members
  for select to authenticated using (private.is_member());
-- Others' pending uploads are noise; show them only to their uploader.
create policy "members read images" on public.images
  for select to authenticated using (
    private.is_member() and (status = 'ready' or uploaded_by = (select auth.uid()))
  );
create policy "owner reads invites" on public.invites
  for select to authenticated using (private.is_owner());
create policy "members read quotas" on public.quota_config
  for select to authenticated using (private.is_member());

-- ── Storage ───────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('frame-images', 'frame-images', false, 524288, array['image/png'])
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Members read (and sign download URLs for) the frame's images. Uploads use signed
-- upload URLs issued by app-api, and deletes go through app-api, so no write policies.
create policy "members read frame images" on storage.objects
  for select to authenticated using (bucket_id = 'frame-images' and private.is_member());
