-- 0001: tables (PLAN.md §7.1).
-- Applied by tools/dev/migrate.ts (dev) and the app's setup wizard (families), in one
-- transaction per file, which also records the version in public.schema_version.
-- Readable tables live in public (exposed through PostgREST under RLS, see 0002).
-- Secrets and server-only state live in private, which is never exposed.

create schema if not exists private;
revoke all on schema private from public;

create table public.schema_version (
  version    int primary key,
  applied_at timestamptz not null default now()
);

-- ── Reference data (seeded from shared/presets.json by seed.sql) ──────────────

create table public.palettes (
  id     text primary key,
  name   text not null,
  colors jsonb not null check (jsonb_typeof(colors) = 'array')
);

create table public.device_models (
  id         text primary key check (id ~ '^[a-z0-9][a-z0-9-]{1,63}$'),
  name       text not null,
  width      int  not null check (width between 1 and 4096),
  height     int  not null check (height between 1 and 4096),
  palette_id text not null references public.palettes (id)
);

-- ── People ────────────────────────────────────────────────────────────────────

create table public.project_members (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  role         text not null check (role in ('admin', 'member')),
  display_name text not null check (char_length(display_name) between 1 and 40),
  invited_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now()
);
-- At most one admin per family space.
create unique index project_members_one_admin on public.project_members ((true)) where role = 'admin';

-- ── Frames ────────────────────────────────────────────────────────────────────

create table public.frames (
  id               uuid primary key default gen_random_uuid(),
  hw_id            text not null unique check (hw_id ~ '^[A-Za-z0-9:_-]{4,64}$'),
  model_id         text not null references public.device_models (id),
  name             text not null check (char_length(name) between 1 and 40),
  fw_version       text check (char_length(fw_version) <= 32),
  manifest_version bigint not null default 1 check (manifest_version >= 1),
  last_seen_at     timestamptz,
  battery_pct      smallint check (battery_pct between 0 and 100),
  rssi             smallint check (rssi between -127 and 0),
  sd_free_bytes    bigint check (sd_free_bytes >= 0),
  created_at       timestamptz not null default now()
);

-- Ownership lives only here (role = 'owner'), one owner per frame.
-- user_id references project_members, so leaving the space removes frame memberships.
create table public.frame_members (
  frame_id   uuid not null references public.frames (id) on delete cascade,
  user_id    uuid not null references public.project_members (user_id) on delete cascade,
  role       text not null check (role in ('owner', 'member')),
  created_at timestamptz not null default now(),
  primary key (frame_id, user_id)
);
create unique index frame_members_one_owner on public.frame_members (frame_id) where role = 'owner';
create index frame_members_user on public.frame_members (user_id);

create table public.frame_settings (
  frame_id         uuid primary key references public.frames (id) on delete cascade,
  image_interval_s int  not null default 14400 check (image_interval_s between 3600 and 172800),
  display_order    text not null default 'random' check (display_order in ('random', 'sequential')),
  sync_interval_s  int  not null default 86400 check (sync_interval_s between 3600 and 172800),
  quiet_start      time,
  quiet_end        time,
  timezone         text not null default 'UTC' check (char_length(timezone) <= 64),
  updated_at       timestamptz not null default now(),
  check ((quiet_start is null) = (quiet_end is null))
);

-- SHA-256 (hex) of each frame's device secret.
create table private.frame_secrets (
  frame_id    uuid primary key references public.frames (id) on delete cascade,
  secret_hash text not null unique check (secret_hash ~ '^[0-9a-f]{64}$')
);

-- Tombstones: lets /sync answer 410 (removed) rather than 401 (unknown secret).
create table private.removed_frames (
  secret_hash text primary key check (secret_hash ~ '^[0-9a-f]{64}$'),
  removed_at  timestamptz not null default now()
);

-- ── Images ────────────────────────────────────────────────────────────────────

create table public.images (
  id           uuid primary key default gen_random_uuid(),
  frame_id     uuid not null references public.frames (id) on delete cascade,
  -- Null once the uploader's account is deleted; the photo stays.
  uploaded_by  uuid references auth.users (id) on delete set null,
  storage_path text not null unique,
  sha256       text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  bytes        int  not null check (bytes between 1 and 524288),
  width        int  not null check (width between 1 and 4096),
  height       int  not null check (height between 1 and 4096),
  -- Set when the image becomes ready (finalize).
  position     double precision,
  status       text not null default 'pending' check (status in ('pending', 'ready')),
  created_at   timestamptz not null default now(),
  unique (frame_id, sha256),
  check ((status = 'ready') = (position is not null))
);
create index images_frame_ready on public.images (frame_id, position) where status = 'ready';
create index images_pending on public.images (created_at) where status = 'pending';
create index images_uploaded_by on public.images (uploaded_by);

-- ── Invites and pairing ───────────────────────────────────────────────────────

create table public.invites (
  id         uuid primary key default gen_random_uuid(),
  -- Null = project-only invite.
  frame_id   uuid references public.frames (id) on delete cascade,
  created_by uuid not null references public.project_members (user_id) on delete cascade,
  expires_at timestamptz not null,
  max_uses   int not null default 1 check (max_uses between 1 and 50),
  uses       int not null default 0 check (uses between 0 and max_uses),
  created_at timestamptz not null default now()
);

create table private.invite_codes (
  invite_id uuid primary key references public.invites (id) on delete cascade,
  code_hash text not null unique check (code_hash ~ '^[0-9a-f]{64}$')
);

create table private.pairing_tokens (
  token_hash text primary key check (token_hash ~ '^[0-9a-f]{64}$'),
  user_id    uuid not null references public.project_members (user_id) on delete cascade,
  frame_name text not null check (char_length(frame_name) between 1 and 40),
  timezone   text not null default 'UTC',
  expires_at timestamptz not null,
  used_at    timestamptz
);

-- ── Quotas ────────────────────────────────────────────────────────────────────

-- Null = unlimited. Values are placeholders (PLAN.md §15).
create table public.quota_config (
  scope      text primary key check (scope in ('frame', 'user', 'project')),
  max_images int check (max_images >= 0),
  max_bytes  bigint check (max_bytes >= 0)
);
insert into public.quota_config (scope, max_images, max_bytes) values
  ('frame',   null, null),
  ('user',    null, null),
  -- ≈ 90 % of the 1 GB free-tier storage limit (PLAN.md §14: verify the limit).
  ('project', null, 966367641);

-- ── Housekeeping ──────────────────────────────────────────────────────────────

create function private.touch_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger frame_settings_touch before update on public.frame_settings
  for each row execute function private.touch_updated_at();
