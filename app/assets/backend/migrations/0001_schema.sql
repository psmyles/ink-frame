-- 0001: tables (PLAN.md §7.1). One project holds one frame.
-- Applied by tools/dev/migrate.ts (dev) and the app's setup wizard, in one transaction
-- per file, which also records the version in public.schema_version.
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

-- ── The frame (exactly one row, created by private.setup_frame) ───────────────

create table public.frame (
  id                  uuid primary key default gen_random_uuid(),
  singleton           boolean not null default true unique check (singleton),
  name                text not null check (char_length(name) between 1 and 40),
  -- Chosen at setup. Every photo is made for this model's resolution and palette.
  model_id            text not null references public.device_models (id),
  -- The connected hardware; null until connected or after a disconnect.
  hw_id               text check (hw_id ~ '^[A-Za-z0-9:_-]{4,64}$'),
  fw_version          text check (char_length(fw_version) <= 32),
  manifest_version    bigint not null default 1 check (manifest_version >= 1),
  last_seen_at        timestamptz,
  battery_pct         smallint check (battery_pct between 0 and 100),
  rssi                smallint check (rssi between -127 and 0),
  sd_free_bytes       bigint check (sd_free_bytes >= 0),
  image_interval_s    int  not null default 14400 check (image_interval_s between 3600 and 172800),
  display_order       text not null default 'random' check (display_order in ('random', 'sequential')),
  sync_interval_s     int  not null default 86400 check (sync_interval_s between 3600 and 172800),
  quiet_start         time,
  quiet_end           time,
  timezone            text not null default 'UTC' check (char_length(timezone) <= 64),
  settings_updated_at timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  -- The manifest version /sync last returned to the connected hardware.
  synced_manifest_version bigint,
  -- The hardware has the latest photos and settings ("Up to date" / "Changes waiting").
  up_to_date          boolean not null generated always as (coalesce(
    hw_id is not null and synced_manifest_version = manifest_version
    and last_seen_at >= settings_updated_at, false)) stored,
  check ((quiet_start is null) = (quiet_end is null))
);

-- ── People ────────────────────────────────────────────────────────────────────

create table public.members (
  user_id      uuid primary key references auth.users (id) on delete cascade,
  role         text not null check (role in ('owner', 'member')),
  display_name text not null check (char_length(display_name) between 1 and 40),
  invited_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default now()
);
-- Exactly one owner (the wizard adds it; nothing removes it).
create unique index members_one_owner on public.members ((true)) where role = 'owner';

-- ── Images ────────────────────────────────────────────────────────────────────

create table public.images (
  id           uuid primary key default gen_random_uuid(),
  -- Null once the uploader's account is deleted; the photo stays.
  uploaded_by  uuid references auth.users (id) on delete set null,
  storage_path text not null unique,
  sha256       text not null unique check (sha256 ~ '^[0-9a-f]{64}$'),
  bytes        int  not null check (bytes between 1 and 524288),
  width        int  not null check (width between 1 and 4096),
  height       int  not null check (height between 1 and 4096),
  -- Set when the image becomes ready (finalize).
  position     double precision,
  status       text not null default 'pending' check (status in ('pending', 'ready')),
  created_at   timestamptz not null default now(),
  check ((status = 'ready') = (position is not null))
);
create index images_ready on public.images (position) where status = 'ready';
create index images_pending on public.images (created_at) where status = 'pending';
create index images_uploaded_by on public.images (uploaded_by);

-- ── Invites and connecting hardware ───────────────────────────────────────────

create table public.invites (
  id         uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.members (user_id) on delete cascade,
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
  user_id    uuid not null references public.members (user_id) on delete cascade,
  expires_at timestamptz not null,
  used_at    timestamptz
);

-- SHA-256 (hex) of the connected hardware's device secret.
create table private.frame_secret (
  frame_id    uuid primary key references public.frame (id) on delete cascade,
  secret_hash text not null unique check (secret_hash ~ '^[0-9a-f]{64}$')
);

-- Tombstones: lets /sync answer 410 (disconnected or replaced) rather than 401.
create table private.removed_devices (
  secret_hash text primary key check (secret_hash ~ '^[0-9a-f]{64}$'),
  removed_at  timestamptz not null default now()
);

-- ── Quotas ────────────────────────────────────────────────────────────────────

-- Null = unlimited. Values are placeholders (PLAN.md §15).
create table public.quota_config (
  scope      text primary key check (scope in ('frame', 'user')),
  max_images int check (max_images >= 0),
  max_bytes  bigint check (max_bytes >= 0)
);
insert into public.quota_config (scope, max_images, max_bytes) values
  -- ≈ 90 % of the 1 GB free-tier storage limit (PLAN.md §14: verify the limit).
  ('frame', null, 966367641),
  ('user',  null, null);

-- ── Setup (called by the wizard with SQL, and by the tests) ───────────────────

create function private.setup_frame(p_name text, p_model_id text, p_timezone text) returns uuid
language sql set search_path = '' as $$
  insert into public.frame (name, model_id, timezone) values (p_name, p_model_id, p_timezone)
  returning id;
$$;

create function private.set_owner(p_user uuid, p_display_name text) returns void
language sql set search_path = '' as $$
  insert into public.members (user_id, role, display_name) values (p_user, 'owner', p_display_name);
$$;
