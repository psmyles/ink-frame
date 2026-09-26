-- 0004: server-side operations behind device-api and app-api (PLAN.md §7.3, §7.4).
--
-- Each write the Edge Functions make is one svc_* call, so it runs in one transaction.
-- The functions handle HTTP, input validation, hashing, tokens and Storage; these do
-- permissions and data. Callable by service_role only (0002 revokes client access to
-- functions in public).
--
-- Errors: private.fail() raises SQLSTATE P0001 with message = the contract's error
-- code, hint = English text, detail = JSON details (or ''). _shared/http.ts maps them.
-- p_user is always the caller's verified auth user id.

-- ── Helpers ───────────────────────────────────────────────────────────────────

create function private.fail(p_code text, p_message text, p_details jsonb default null)
returns void language plpgsql as $$
begin
  raise exception using errcode = 'P0001', message = p_code, hint = p_message,
    detail = coalesce(p_details::text, '');
end;
$$;

-- Returns the caller's role ('owner' / 'member').
create function private.require_member(p_user uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare r text;
begin
  select role into r from public.members where user_id = p_user;
  if r is null then
    perform private.fail('not_member', 'Not a member of this frame.');
  end if;
  return r;
end;
$$;

create function private.require_owner(p_user uuid) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if private.require_member(p_user) <> 'owner' then
    perform private.fail('not_owner', 'Only the person who set up this frame can do this.');
  end if;
end;
$$;

create function private.bump_manifest() returns void
language sql security definer set search_path = '' as $$
  update public.frame set manifest_version = manifest_version + 1 where true;
$$;

create function private.image_json(i public.images) returns jsonb
language sql immutable as $$
  select to_jsonb(i) - 'storage_path';
$$;

create function private.frame_json(f public.frame) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'id', f.id, 'name', f.name, 'model_id', f.model_id, 'connected', f.hw_id is not null,
    'up_to_date', f.up_to_date, 'fw_version', f.fw_version, 'last_seen_at', f.last_seen_at, 'battery_pct', f.battery_pct,
    'image_interval_s', f.image_interval_s, 'display_order', f.display_order,
    'sync_interval_s', f.sync_interval_s,
    'quiet_start', to_char(f.quiet_start, 'HH24:MI'), 'quiet_end', to_char(f.quiet_end, 'HH24:MI'),
    'timezone', f.timezone
  );
$$;

-- Raises quota_exceeded if adding one image of p_new_bytes would pass the limit.
create function private.check_quota(p_scope text, p_images bigint, p_bytes bigint, p_new_bytes int)
returns void language plpgsql stable security definer set search_path = '' as $$
declare q public.quota_config;
begin
  select * into q from public.quota_config where scope = p_scope;
  if q.max_images is not null and p_images + 1 > q.max_images then
    perform private.fail('quota_exceeded', format('The %s image limit is reached.', p_scope),
      jsonb_build_object('scope', p_scope, 'limit', q.max_images, 'used', p_images, 'unit', 'images'));
  end if;
  if q.max_bytes is not null and p_bytes + p_new_bytes > q.max_bytes then
    perform private.fail('quota_exceeded', format('The %s storage limit is reached.', p_scope),
      jsonb_build_object('scope', p_scope, 'limit', q.max_bytes, 'used', p_bytes, 'unit', 'bytes'));
  end if;
end;
$$;

-- Tombstones the connected device's secret (it gets 410) and forgets the hardware.
create function private.disconnect() returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into private.removed_devices (secret_hash)
    select secret_hash from private.frame_secret on conflict do nothing;
  delete from private.frame_secret where true;
  update public.frame set hw_id = null, fw_version = null, last_seen_at = null,
    battery_pct = null, rssi = null, sd_free_bytes = null, synced_manifest_version = null where true;
end;
$$;

-- ── device-api ────────────────────────────────────────────────────────────────

create function public.svc_claim_frame(
  p_token_hash text, p_hw_id text, p_model_id text, p_fw_version text, p_secret_hash text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  t private.pairing_tokens;
  f public.frame;
begin
  select * into t from private.pairing_tokens where token_hash = p_token_hash for update;
  if not found or t.used_at is not null or t.expires_at < now() then
    perform private.fail('invalid_pairing_token', 'The pairing token is unknown, expired or already used.');
  end if;
  if not exists (select 1 from public.device_models where id = p_model_id) then
    perform private.fail('unknown_model', format('Unknown model %s.', p_model_id));
  end if;

  select * into f from public.frame for update;
  if p_model_id <> f.model_id then
    perform private.fail('model_mismatch',
      format('This hardware is a %s; the frame is set up for %s.', p_model_id, f.model_id),
      jsonb_build_object('frame_model', f.model_id, 'device_model', p_model_id));
  end if;

  if f.hw_id is distinct from p_hw_id then
    -- New or replacement hardware: the old device (if any) gets 410. Photos stay.
    perform private.disconnect();
  end if;
  -- Same hardware re-provisioning just rotates the secret: the old one gets 401.
  delete from private.frame_secret where true;
  insert into private.frame_secret (frame_id, secret_hash) values (f.id, p_secret_hash);
  update public.frame set hw_id = p_hw_id, fw_version = p_fw_version where true;

  update private.pairing_tokens set used_at = now() where token_hash = p_token_hash;
  return f.id;
end;
$$;

-- Returns {manifest_version, settings (with IANA timezone), images?}.
-- images (with storage_path) is null when p_manifest_version is current.
create function public.svc_sync_frame(
  p_secret_hash text, p_manifest_version bigint, p_fw_version text,
  p_battery_pct int, p_rssi int, p_sd_free_bytes bigint
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare f public.frame;
begin
  if not exists (select 1 from private.frame_secret where secret_hash = p_secret_hash) then
    if exists (select 1 from private.removed_devices where secret_hash = p_secret_hash) then
      perform private.fail('frame_removed', 'This device was disconnected from the frame.');
    end if;
    perform private.fail('invalid_device_secret', 'Unknown device secret.');
  end if;

  update public.frame set
    last_seen_at = now(), fw_version = p_fw_version, battery_pct = p_battery_pct,
    rssi = p_rssi, sd_free_bytes = p_sd_free_bytes, synced_manifest_version = manifest_version
  where true
  returning * into f;

  return jsonb_build_object(
    'manifest_version', f.manifest_version,
    'settings', jsonb_build_object(
      'image_interval_s', f.image_interval_s, 'display_order', f.display_order,
      'sync_interval_s', f.sync_interval_s,
      'quiet_start', to_char(f.quiet_start, 'HH24:MI'), 'quiet_end', to_char(f.quiet_end, 'HH24:MI'),
      'timezone', f.timezone),
    'images', case when p_manifest_version = f.manifest_version then null else (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', i.id, 'sha256', i.sha256, 'bytes', i.bytes, 'position', i.position,
        'storage_path', i.storage_path) order by i.position), '[]'::jsonb)
      from public.images i where i.status = 'ready'
    ) end
  );
end;
$$;

-- ── app-api: frame ────────────────────────────────────────────────────────────

-- p_patch: {name?, model_id?, clear_photos?}. Returns {frame, storage_paths}.
create function public.svc_update_frame(p_user uuid, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  f public.frame;
  n int;
  paths text[] := '{}';
begin
  perform private.require_owner(p_user);
  select * into f from public.frame for update;

  if p_patch ? 'model_id' and p_patch->>'model_id' <> f.model_id then
    if not exists (select 1 from public.device_models where id = p_patch->>'model_id') then
      perform private.fail('unknown_model', format('Unknown model %s.', p_patch->>'model_id'));
    end if;
    select count(*) into n from public.images;
    if n > 0 and not coalesce((p_patch->>'clear_photos')::boolean, false) then
      perform private.fail('photos_would_be_cleared',
        format('Changing the panel model deletes all %s photos.', n), jsonb_build_object('images', n));
    end if;
    with d as (delete from public.images where true returning storage_path)
    select coalesce(array_agg(storage_path), '{}') into paths from d;
    -- The connected hardware is the old model; it wipes itself.
    perform private.disconnect();
    update public.frame set model_id = p_patch->>'model_id' where true;
    perform private.bump_manifest();
  end if;

  if p_patch ? 'name' then
    update public.frame set name = p_patch->>'name' where true;
  end if;

  select * into f from public.frame;
  return jsonb_build_object('frame', private.frame_json(f), 'storage_paths', to_jsonb(paths));
end;
$$;

-- p_patch holds only the fields to change; a JSON null clears quiet hours.
create function public.svc_update_frame_settings(p_user uuid, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare f public.frame;
begin
  perform private.require_owner(p_user);
  select * into f from public.frame for update;

  if p_patch ? 'image_interval_s' then f.image_interval_s := (p_patch->>'image_interval_s')::int; end if;
  if p_patch ? 'display_order'    then f.display_order    := p_patch->>'display_order'; end if;
  if p_patch ? 'sync_interval_s'  then f.sync_interval_s  := (p_patch->>'sync_interval_s')::int; end if;
  if p_patch ? 'quiet_start'      then f.quiet_start      := (p_patch->>'quiet_start')::time; end if;
  if p_patch ? 'quiet_end'        then f.quiet_end        := (p_patch->>'quiet_end')::time; end if;
  if p_patch ? 'timezone'         then f.timezone         := p_patch->>'timezone'; end if;

  if (f.quiet_start is null) <> (f.quiet_end is null) then
    perform private.fail('quiet_hours_incomplete', 'Set both quiet-hours times, or neither.');
  end if;

  update public.frame set
    image_interval_s = f.image_interval_s, display_order = f.display_order,
    sync_interval_s = f.sync_interval_s, quiet_start = f.quiet_start,
    quiet_end = f.quiet_end, timezone = f.timezone, settings_updated_at = now()
  where true
  returning * into f;
  return private.frame_json(f);
end;
$$;

create function public.svc_create_pairing_token(p_user uuid, p_token_hash text) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare exp timestamptz := now() + interval '10 minutes';
begin
  perform private.require_owner(p_user);
  insert into private.pairing_tokens (token_hash, user_id, expires_at) values (p_token_hash, p_user, exp);
  return exp;
end;
$$;

create function public.svc_disconnect_frame(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner(p_user);
  perform private.disconnect();
end;
$$;

-- ── app-api: images ───────────────────────────────────────────────────────────

-- Returns {image_id, storage_path}. Reuses a pending row with the same hash.
create function public.svc_request_upload(
  p_user uuid, p_sha256 text, p_bytes int, p_width int, p_height int
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  m public.device_models;
  existing public.images;
  n bigint;
  b bigint;
  new_id uuid := gen_random_uuid();
  path text;
begin
  perform private.require_member(p_user);

  select dm.* into m from public.device_models dm join public.frame f on f.model_id = dm.id;
  if p_width <> m.width or p_height <> m.height then
    perform private.fail('dimension_mismatch',
      format('Image is %sx%s; this frame needs %sx%s.', p_width, p_height, m.width, m.height),
      jsonb_build_object('expected_width', m.width, 'expected_height', m.height));
  end if;

  select * into existing from public.images where sha256 = p_sha256 for update;
  if found then
    if existing.status = 'ready' then
      perform private.fail('duplicate_image', 'This photo is already on the frame.',
        jsonb_build_object('image_id', existing.id));
    end if;
    update public.images set uploaded_by = p_user, bytes = p_bytes, created_at = now()
      where id = existing.id;
    return jsonb_build_object('image_id', existing.id, 'storage_path', existing.storage_path);
  end if;

  select count(*), coalesce(sum(bytes), 0) into n, b from public.images;
  perform private.check_quota('frame', n, b, p_bytes);
  select count(*), coalesce(sum(bytes), 0) into n, b from public.images where uploaded_by = p_user;
  perform private.check_quota('user', n, b, p_bytes);

  path := new_id || '.png';
  insert into public.images (id, uploaded_by, storage_path, sha256, bytes, width, height)
    values (new_id, p_user, path, p_sha256, p_bytes, p_width, p_height);
  return jsonb_build_object('image_id', new_id, 'storage_path', path);
end;
$$;

-- Returns the image (with storage_path) for finalize to check the uploaded object.
create function public.svc_get_upload(p_user uuid, p_image uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare i public.images;
begin
  perform private.require_member(p_user);
  select * into i from public.images where id = p_image;
  if not found then
    perform private.fail('image_not_found', 'Image not found.');
  end if;
  if i.uploaded_by is distinct from p_user then
    perform private.fail('not_uploader', 'Only the uploader can finalize this image.');
  end if;
  return to_jsonb(i);
end;
$$;

-- Marks a pending image ready at the end of the order. Idempotent.
create function public.svc_mark_ready(p_user uuid, p_image uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare i public.images;
begin
  perform private.require_member(p_user);
  select * into i from public.images where id = p_image for update;
  if not found then
    perform private.fail('image_not_found', 'Image not found.');
  end if;
  if i.uploaded_by is distinct from p_user then
    perform private.fail('not_uploader', 'Only the uploader can finalize this image.');
  end if;
  if i.status = 'ready' then
    return private.image_json(i);
  end if;

  update public.images set status = 'ready', position = (
    select coalesce(max(position), 0) + 1 from public.images where status = 'ready'
  ) where id = p_image returning * into i;
  perform private.bump_manifest();
  return private.image_json(i);
end;
$$;

-- Drops a pending image whose upload failed verification.
create function public.svc_discard_upload(p_user uuid, p_image uuid) returns void
language sql security definer set search_path = '' as $$
  delete from public.images where id = p_image and uploaded_by = p_user and status = 'pending';
$$;

-- All-or-nothing. Returns {deleted_ids, storage_paths}.
create function public.svc_delete_images(p_user uuid, p_ids uuid[]) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  forbidden uuid[];
  ids uuid[];
  paths text[];
  any_ready boolean;
begin
  if private.require_member(p_user) <> 'owner' then
    select array_agg(i.id) into forbidden from public.images i
      where i.id = any(p_ids) and i.uploaded_by is distinct from p_user;
    if forbidden is not null then
      perform private.fail('not_allowed', 'Only the uploader or the frame''s owner can delete these photos.',
        jsonb_build_object('image_ids', forbidden));
    end if;
  end if;

  with d as (delete from public.images where id = any(p_ids) returning id, storage_path, status)
  select coalesce(array_agg(id), '{}'), coalesce(array_agg(storage_path), '{}'),
         coalesce(bool_or(status = 'ready'), false)
    into ids, paths, any_ready from d;
  if any_ready then
    perform private.bump_manifest();
  end if;
  return jsonb_build_object('deleted_ids', to_jsonb(ids), 'storage_paths', to_jsonb(paths));
end;
$$;

-- Places p_image right after p_after (null = first). Positions are midpoints;
-- the order is renumbered 1, 2, 3… when a gap gets too small.
create function public.svc_reorder_image(p_user uuid, p_image uuid, p_after uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  i public.images;
  after_pos double precision;
  next_pos double precision;
  attempt int;
begin
  perform private.require_owner(p_user);
  select * into i from public.images where id = p_image and status = 'ready' for update;
  if not found then
    perform private.fail('image_not_found', 'Image not found.');
  end if;
  if p_after = p_image then
    return private.image_json(i);
  end if;

  for attempt in 1..2 loop
    if p_after is null then
      after_pos := null;
    else
      select position into after_pos from public.images where id = p_after and status = 'ready';
      if not found then
        perform private.fail('image_not_found', 'The image to place after was not found.');
      end if;
    end if;
    select min(position) into next_pos from public.images
      where status = 'ready' and id <> p_image and (after_pos is null or position > after_pos);

    exit when after_pos is null or next_pos is null or next_pos - after_pos > 1e-9;

    -- Gap too small: renumber and try again.
    update public.images im set position = r.n
      from (select id, row_number() over (order by position) as n
            from public.images where status = 'ready') r
      where im.id = r.id;
  end loop;

  update public.images set position = case
      when after_pos is null and next_pos is null then 1
      when after_pos is null then next_pos - 1
      when next_pos is null then after_pos + 1
      else (after_pos + next_pos) / 2
    end
  where id = p_image returning * into i;
  perform private.bump_manifest();
  return private.image_json(i);
end;
$$;

-- ── app-api: people ───────────────────────────────────────────────────────────

create function public.svc_create_invite(p_user uuid, p_max_uses int, p_expires_in_s int, p_code_hash text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare inv public.invites;
begin
  perform private.require_owner(p_user);
  insert into public.invites (created_by, expires_at, max_uses)
    values (p_user, now() + make_interval(secs => p_expires_in_s), p_max_uses)
    returning * into inv;
  insert into private.invite_codes (invite_id, code_hash) values (inv.id, p_code_hash);
  return jsonb_build_object('invite_id', inv.id, 'expires_at', inv.expires_at, 'max_uses', inv.max_uses);
end;
$$;

create function public.svc_revoke_invite(p_user uuid, p_invite uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_owner(p_user);
  delete from public.invites where id = p_invite;
  if not found then
    perform private.fail('invite_not_found', 'Invite not found.');
  end if;
end;
$$;

-- The one operation that doesn't need an existing membership. Returns {role}.
create function public.svc_accept_invite(p_user uuid, p_code_hash text, p_display_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  inv public.invites;
  r text;
begin
  select i.* into inv from public.invites i
    join private.invite_codes c on c.invite_id = i.id
    where c.code_hash = p_code_hash
    for update of i;
  if not found or inv.expires_at < now() or inv.uses >= inv.max_uses then
    perform private.fail('invalid_invite', 'This invite code is not valid.');
  end if;

  select role into r from public.members where user_id = p_user;
  if r is null then
    if p_display_name is null then
      perform private.fail('display_name_required', 'A display name is required to join.');
    end if;
    insert into public.members (user_id, role, display_name, invited_by)
      values (p_user, 'member', p_display_name, inv.created_by);
    update public.invites set uses = uses + 1 where id = inv.id;
    r := 'member';
  end if;
  return jsonb_build_object('role', r);
end;
$$;

-- The owner removes someone, or a member leaves. Their photos stay.
create function public.svc_remove_member(p_user uuid, p_target uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  caller_role text;
  target_role text;
begin
  caller_role := private.require_member(p_user);
  if p_target <> p_user and caller_role <> 'owner' then
    perform private.fail('not_allowed', 'Only the person who set up this frame can remove people.');
  end if;
  select role into target_role from public.members where user_id = p_target;
  if target_role is null then
    perform private.fail('member_not_found', 'Not a member of this frame.');
  end if;
  if target_role = 'owner' then
    perform private.fail('cannot_remove_owner', 'The owner can''t be removed. Delete the frame instead.');
  end if;
  delete from public.members where user_id = p_target;
end;
$$;

-- ── app-api: account ──────────────────────────────────────────────────────────

create function public.svc_update_me(p_user uuid, p_display_name text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare m public.members;
begin
  perform private.require_member(p_user);
  update public.members set display_name = p_display_name where user_id = p_user returning * into m;
  return jsonb_build_object('user_id', m.user_id, 'display_name', m.display_name, 'role', m.role);
end;
$$;

-- Removes a member (the function then deletes the auth user). Returns {storage_paths}.
create function public.svc_delete_me(p_user uuid, p_delete_photos boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  paths text[] := '{}';
  any_ready boolean := false;
begin
  if private.require_member(p_user) = 'owner' then
    perform private.fail('owner_must_delete_frame',
      'The person who set up this frame deletes their account by deleting the frame.');
  end if;
  if p_delete_photos then
    with d as (delete from public.images where uploaded_by = p_user returning storage_path, status)
    select coalesce(array_agg(storage_path), '{}'), coalesce(bool_or(status = 'ready'), false)
      into paths, any_ready from d;
    if any_ready then
      perform private.bump_manifest();
    end if;
  end if;
  delete from public.members where user_id = p_user;
  return jsonb_build_object('storage_paths', to_jsonb(paths));
end;
$$;

-- Returns {frame, users[]} (UsageEntry shape, without free_tier_bytes).
create function public.svc_usage(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  r text;
  qf public.quota_config;
  qu public.quota_config;
begin
  r := private.require_member(p_user);
  select * into qf from public.quota_config where scope = 'frame';
  select * into qu from public.quota_config where scope = 'user';
  return jsonb_build_object(
    'frame', (
      select jsonb_build_object('images', count(*), 'bytes', coalesce(sum(bytes), 0),
        'max_images', qf.max_images, 'max_bytes', qf.max_bytes)
      from public.images),
    'users', (
      select coalesce(jsonb_agg(jsonb_build_object('user_id', m.user_id,
        'images', (select count(*) from public.images i where i.uploaded_by = m.user_id),
        'bytes', (select coalesce(sum(bytes), 0) from public.images i where i.uploaded_by = m.user_id),
        'max_images', qu.max_images, 'max_bytes', qu.max_bytes)), '[]'::jsonb)
      from public.members m where r = 'owner' or m.user_id = p_user)
  );
end;
$$;

-- ── Maintenance ───────────────────────────────────────────────────────────────

create function public.svc_check_maintenance_secret(p_secret text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from private.config where key = 'maintenance_secret' and value = p_secret);
$$;

-- Objects older than an hour that no image row points to.
create function public.svc_orphan_objects(p_limit int) returns setof text
language sql stable security definer set search_path = '' as $$
  select o.name from storage.objects o
  where o.bucket_id = 'frame-images'
    and o.created_at < now() - interval '1 hour'
    and not exists (select 1 from public.images i where i.storage_path = o.name)
  limit p_limit;
$$;

-- ── Privileges ────────────────────────────────────────────────────────────────

revoke execute on all functions in schema private from public, anon;
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;
-- RLS helpers stay callable by authenticated (0002).
grant execute on function private.is_member(), private.is_owner() to authenticated;
