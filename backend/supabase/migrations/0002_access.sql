-- 0002: privileges, RLS, storage bucket (PLAN.md §7.1, §7.2).
-- Members may only SELECT rows they belong to. Every write goes through app-api
-- (service role), so there are no insert/update/delete policies at all.

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

grant select on
  public.project_members,
  public.frames,
  public.frame_members,
  public.frame_settings,
  public.images,
  public.invites,
  public.quota_config
to authenticated;

-- RLS helper functions live in private and run as their owner, so they can read the
-- membership tables without recursing through RLS.
grant usage on schema private to authenticated;

-- ── Helpers ───────────────────────────────────────────────────────────────────

create function private.is_project_member() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.project_members m where m.user_id = (select auth.uid())
  );
$$;

create function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.project_members m
    where m.user_id = (select auth.uid()) and m.role = 'admin'
  );
$$;

create function private.is_frame_member(f uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.frame_members m
    where m.frame_id = f and m.user_id = (select auth.uid())
  );
$$;

create function private.is_frame_owner(f uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.frame_members m
    where m.frame_id = f and m.user_id = (select auth.uid()) and m.role = 'owner'
  );
$$;

-- Storage object names are '{frame_id}/{image_id}.png'. Compared as text so a
-- malformed name is simply "not readable" instead of a cast error.
create function private.can_read_frame_object(object_name text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.frame_members m
    where m.frame_id::text = split_part(object_name, '/', 1)
      and m.user_id = (select auth.uid())
  );
$$;

revoke execute on all functions in schema private from public, anon;
grant execute on function
  private.is_project_member(),
  private.is_admin(),
  private.is_frame_member(uuid),
  private.is_frame_owner(uuid),
  private.can_read_frame_object(text)
to authenticated;

-- ── RLS ───────────────────────────────────────────────────────────────────────

alter table public.schema_version  enable row level security;
alter table public.palettes        enable row level security;
alter table public.device_models   enable row level security;
alter table public.project_members enable row level security;
alter table public.frames          enable row level security;
alter table public.frame_members   enable row level security;
alter table public.frame_settings  enable row level security;
alter table public.images          enable row level security;
alter table public.invites         enable row level security;
alter table public.quota_config    enable row level security;

create policy "anyone reads schema version" on public.schema_version
  for select to anon, authenticated using (true);
create policy "anyone reads palettes" on public.palettes
  for select to anon, authenticated using (true);
create policy "anyone reads device models" on public.device_models
  for select to anon, authenticated using (true);

create policy "members read members" on public.project_members
  for select to authenticated using (private.is_project_member());

create policy "frame members read frames" on public.frames
  for select to authenticated using (private.is_frame_member(id));

create policy "frame members read frame members" on public.frame_members
  for select to authenticated using (private.is_frame_member(frame_id));

create policy "frame members read settings" on public.frame_settings
  for select to authenticated using (private.is_frame_member(frame_id));

-- Others' pending uploads are noise; show them only to their uploader.
create policy "frame members read images" on public.images
  for select to authenticated using (
    private.is_frame_member(frame_id)
    and (status = 'ready' or uploaded_by = (select auth.uid()))
  );

create policy "creator, frame owner or admin read invites" on public.invites
  for select to authenticated using (
    created_by = (select auth.uid())
    or private.is_admin()
    or (frame_id is not null and private.is_frame_owner(frame_id))
  );

create policy "members read quotas" on public.quota_config
  for select to authenticated using (private.is_project_member());

-- ── Storage ───────────────────────────────────────────────────────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('frame-images', 'frame-images', false, 524288, array['image/png'])
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Members read (and sign download URLs for) their frames' images. Uploads use signed
-- upload URLs issued by app-api, and deletes go through app-api, so no write policies.
create policy "frame members read frame images" on storage.objects
  for select to authenticated using (
    bucket_id = 'frame-images' and private.can_read_frame_object(name)
  );
