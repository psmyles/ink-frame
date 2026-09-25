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

create function private.require_member(p_user uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare r text;
begin
  select role into r from public.project_members where user_id = p_user;
  if r is null then
    perform private.fail('not_project_member', 'Not a member of this family space.');
  end if;
  return r;
end;
$$;

create function private.require_admin(p_user uuid) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if private.require_member(p_user) <> 'admin' then
    perform private.fail('not_admin', 'Only the admin can do this.');
  end if;
end;
$$;

-- Returns the caller's frame role ('owner' / 'member').
create function private.require_frame_member(p_user uuid, p_frame uuid) returns text
language plpgsql stable security definer set search_path = '' as $$
declare r text;
begin
  perform private.require_member(p_user);
  if not exists (select 1 from public.frames where id = p_frame) then
    perform private.fail('frame_not_found', 'Frame not found.');
  end if;
  select role into r from public.frame_members where frame_id = p_frame and user_id = p_user;
  if r is null then
    perform private.fail('not_frame_member', 'Not a member of this frame.');
  end if;
  return r;
end;
$$;

create function private.require_frame_owner(p_user uuid, p_frame uuid) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if private.require_frame_member(p_user, p_frame) <> 'owner' then
    perform private.fail('not_frame_owner', 'Only the frame owner can do this.');
  end if;
end;
$$;

create function private.bump_manifest(p_frames uuid[]) returns void
language sql security definer set search_path = '' as $$
  update public.frames set manifest_version = manifest_version + 1 where id = any(p_frames);
$$;

create function private.image_json(i public.images) returns jsonb
language sql immutable as $$
  select to_jsonb(i) - 'storage_path';
$$;

create function private.settings_json(s public.frame_settings) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'frame_id', s.frame_id,
    'image_interval_s', s.image_interval_s,
    'display_order', s.display_order,
    'sync_interval_s', s.sync_interval_s,
    'quiet_start', to_char(s.quiet_start, 'HH24:MI'),
    'quiet_end', to_char(s.quiet_end, 'HH24:MI'),
    'timezone', s.timezone,
    'updated_at', s.updated_at
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

-- Deletes a frame and leaves a tombstone so its next sync gets 410. Returns the
-- storage paths of its images, for the caller to delete from Storage.
create function private.delete_frame(p_frame uuid) returns text[]
language plpgsql security definer set search_path = '' as $$
declare paths text[];
begin
  insert into private.removed_frames (secret_hash)
    select secret_hash from private.frame_secrets where frame_id = p_frame
    on conflict do nothing;
  select coalesce(array_agg(storage_path), '{}') into paths from public.images where frame_id = p_frame;
  delete from public.frames where id = p_frame;
  return paths;
end;
$$;

-- Moves ownership of every frame p_from owns to p_to.
create function private.transfer_frames(p_from uuid, p_to uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare f uuid;
begin
  for f in select frame_id from public.frame_members where user_id = p_from and role = 'owner' loop
    delete from public.frame_members where frame_id = f and user_id = p_from;
    insert into public.frame_members (frame_id, user_id, role) values (f, p_to, 'owner')
      on conflict (frame_id, user_id) do update set role = 'owner';
  end loop;
end;
$$;

-- ── device-api ────────────────────────────────────────────────────────────────

create function public.svc_claim_frame(
  p_token_hash text, p_hw_id text, p_model_id text, p_fw_version text, p_secret_hash text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  t private.pairing_tokens;
  f uuid;
  owner uuid;
begin
  select * into t from private.pairing_tokens where token_hash = p_token_hash for update;
  if not found or t.used_at is not null or t.expires_at < now() then
    perform private.fail('invalid_pairing_token', 'The pairing token is unknown, expired or already used.');
  end if;
  if not exists (select 1 from public.device_models where id = p_model_id) then
    perform private.fail('unknown_model', format('Unknown model %s.', p_model_id));
  end if;

  select id into f from public.frames where hw_id = p_hw_id for update;
  if found then
    select user_id into owner from public.frame_members where frame_id = f and role = 'owner';
    if owner is distinct from t.user_id then
      perform private.fail('hw_id_conflict', 'This frame is paired to someone else in this family space.');
    end if;
    -- Re-provisioning by the same owner: keep the frame, rotate the secret.
    update public.frames set model_id = p_model_id, fw_version = p_fw_version where id = f;
    insert into private.frame_secrets (frame_id, secret_hash) values (f, p_secret_hash)
      on conflict (frame_id) do update set secret_hash = excluded.secret_hash;
  else
    insert into public.frames (hw_id, model_id, name, fw_version)
      values (p_hw_id, p_model_id, t.frame_name, p_fw_version) returning id into f;
    insert into public.frame_settings (frame_id, timezone) values (f, t.timezone);
    insert into public.frame_members (frame_id, user_id, role) values (f, t.user_id, 'owner');
    insert into private.frame_secrets (frame_id, secret_hash) values (f, p_secret_hash);
  end if;

  update private.pairing_tokens set used_at = now() where token_hash = p_token_hash;
  return f;
end;
$$;

-- Returns {frame_id, manifest_version, settings (with IANA timezone), images?}.
-- images (with storage_path) is null when p_manifest_version is current.
create function public.svc_sync_frame(
  p_secret_hash text, p_manifest_version bigint, p_fw_version text,
  p_battery_pct int, p_rssi int, p_sd_free_bytes bigint
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  f public.frames;
  s public.frame_settings;
begin
  select fr.* into f from public.frames fr
    join private.frame_secrets fs on fs.frame_id = fr.id
    where fs.secret_hash = p_secret_hash;
  if not found then
    if exists (select 1 from private.removed_frames where secret_hash = p_secret_hash) then
      perform private.fail('frame_removed', 'This frame was removed.');
    end if;
    perform private.fail('invalid_device_secret', 'Unknown device secret.');
  end if;

  update public.frames set
    last_seen_at = now(), fw_version = p_fw_version, battery_pct = p_battery_pct,
    rssi = p_rssi, sd_free_bytes = p_sd_free_bytes
  where id = f.id;

  select * into s from public.frame_settings where frame_id = f.id;

  return jsonb_build_object(
    'frame_id', f.id,
    'manifest_version', f.manifest_version,
    'settings', private.settings_json(s) - 'frame_id' - 'updated_at',
    'images', case when p_manifest_version = f.manifest_version then null else (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', i.id, 'sha256', i.sha256, 'bytes', i.bytes, 'position', i.position,
        'storage_path', i.storage_path) order by i.position), '[]'::jsonb)
      from public.images i where i.frame_id = f.id and i.status = 'ready'
    ) end
  );
end;
$$;

-- ── app-api: pairing ──────────────────────────────────────────────────────────

create function public.svc_create_pairing_token(
  p_user uuid, p_token_hash text, p_frame_name text, p_timezone text
) returns timestamptz language plpgsql security definer set search_path = '' as $$
declare exp timestamptz := now() + interval '10 minutes';
begin
  perform private.require_member(p_user);
  insert into private.pairing_tokens (token_hash, user_id, frame_name, timezone, expires_at)
    values (p_token_hash, p_user, p_frame_name, p_timezone, exp);
  return exp;
end;
$$;

-- ── app-api: images ───────────────────────────────────────────────────────────

-- Returns {image_id, storage_path}. Reuses a pending row with the same hash.
create function public.svc_request_upload(
  p_user uuid, p_frame uuid, p_sha256 text, p_bytes int, p_width int, p_height int
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  m public.device_models;
  existing public.images;
  n bigint;
  b bigint;
  new_id uuid := gen_random_uuid();
  path text;
begin
  perform private.require_frame_member(p_user, p_frame);

  select dm.* into m from public.device_models dm join public.frames f on f.model_id = dm.id
    where f.id = p_frame;
  if p_width <> m.width or p_height <> m.height then
    perform private.fail('dimension_mismatch',
      format('Image is %sx%s; this frame needs %sx%s.', p_width, p_height, m.width, m.height),
      jsonb_build_object('expected_width', m.width, 'expected_height', m.height));
  end if;

  select * into existing from public.images where frame_id = p_frame and sha256 = p_sha256 for update;
  if found then
    if existing.status = 'ready' then
      perform private.fail('duplicate_image', 'This photo is already on the frame.',
        jsonb_build_object('image_id', existing.id));
    end if;
    update public.images set uploaded_by = p_user, bytes = p_bytes, created_at = now()
      where id = existing.id;
    return jsonb_build_object('image_id', existing.id, 'storage_path', existing.storage_path);
  end if;

  select count(*), coalesce(sum(bytes), 0) into n, b from public.images where frame_id = p_frame;
  perform private.check_quota('frame', n, b, p_bytes);
  select count(*), coalesce(sum(bytes), 0) into n, b from public.images where uploaded_by = p_user;
  perform private.check_quota('user', n, b, p_bytes);
  select count(*), coalesce(sum(bytes), 0) into n, b from public.images;
  perform private.check_quota('project', n, b, p_bytes);

  path := p_frame || '/' || new_id || '.png';
  insert into public.images (id, frame_id, uploaded_by, storage_path, sha256, bytes, width, height)
    values (new_id, p_frame, p_user, path, p_sha256, p_bytes, p_width, p_height);
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

-- Marks a pending image ready at the end of the frame's order. Idempotent.
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
    select coalesce(max(position), 0) + 1 from public.images
    where frame_id = i.frame_id and status = 'ready'
  ) where id = p_image returning * into i;
  perform private.bump_manifest(array[i.frame_id]);
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
  frames uuid[];
begin
  perform private.require_member(p_user);

  -- Your own photos (even on a frame you've left), or any photo on a frame you own.
  select array_agg(i.id) into forbidden from public.images i
    where i.id = any(p_ids)
      and i.uploaded_by is distinct from p_user
      and not exists (select 1 from public.frame_members fm
                      where fm.frame_id = i.frame_id and fm.user_id = p_user and fm.role = 'owner');
  if forbidden is not null then
    perform private.fail('not_allowed', 'Some of these photos can only be deleted by their uploader or the frame owner.',
      jsonb_build_object('image_ids', forbidden));
  end if;

  with d as (
    delete from public.images where id = any(p_ids) returning id, frame_id, storage_path, status
  )
  select coalesce(array_agg(id), '{}'), coalesce(array_agg(storage_path), '{}'),
         coalesce(array_agg(distinct frame_id) filter (where status = 'ready'), '{}')
    into ids, paths, frames from d;
  perform private.bump_manifest(frames);
  return jsonb_build_object('deleted_ids', to_jsonb(ids), 'storage_paths', to_jsonb(paths));
end;
$$;

-- Places p_image right after p_after (null = first). Positions are midpoints;
-- the frame is renumbered 1, 2, 3… when a gap gets too small.
create function public.svc_reorder_image(p_user uuid, p_image uuid, p_after uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  i public.images;
  after_pos double precision;
  next_pos double precision;
  attempt int;
begin
  perform private.require_member(p_user);
  select * into i from public.images where id = p_image and status = 'ready' for update;
  if not found then
    perform private.fail('image_not_found', 'Image not found.');
  end if;
  perform private.require_frame_owner(p_user, i.frame_id);
  if p_after = p_image then
    return private.image_json(i);
  end if;

  for attempt in 1..2 loop
    if p_after is null then
      after_pos := null;
    else
      select position into after_pos from public.images
        where id = p_after and frame_id = i.frame_id and status = 'ready';
      if not found then
        perform private.fail('image_not_found', 'The image to place after is not on this frame.');
      end if;
    end if;
    select min(position) into next_pos from public.images
      where frame_id = i.frame_id and status = 'ready' and id <> p_image
        and (after_pos is null or position > after_pos);

    exit when after_pos is null or next_pos is null or next_pos - after_pos > 1e-9;

    -- Gap too small: renumber the frame and try again.
    update public.images im set position = r.n
      from (select id, row_number() over (order by position) as n from public.images
            where frame_id = i.frame_id and status = 'ready') r
      where im.id = r.id;
  end loop;

  update public.images set position = case
      when after_pos is null and next_pos is null then 1
      when after_pos is null then next_pos - 1
      when next_pos is null then after_pos + 1
      else (after_pos + next_pos) / 2
    end
  where id = p_image returning * into i;
  perform private.bump_manifest(array[i.frame_id]);
  return private.image_json(i);
end;
$$;

-- ── app-api: frames ───────────────────────────────────────────────────────────

create function public.svc_rename_frame(p_user uuid, p_frame uuid, p_name text) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_frame_owner(p_user, p_frame);
  update public.frames set name = p_name where id = p_frame;
  return jsonb_build_object('frame_id', p_frame, 'name', p_name);
end;
$$;

-- Returns {storage_paths}.
create function public.svc_delete_frame(p_user uuid, p_frame uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_frame_owner(p_user, p_frame);
  return jsonb_build_object('storage_paths', to_jsonb(private.delete_frame(p_frame)));
end;
$$;

-- p_patch holds only the fields to change; a JSON null clears quiet hours.
create function public.svc_update_frame_settings(p_user uuid, p_frame uuid, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare s public.frame_settings;
begin
  perform private.require_frame_owner(p_user, p_frame);
  select * into s from public.frame_settings where frame_id = p_frame for update;

  if p_patch ? 'image_interval_s' then s.image_interval_s := (p_patch->>'image_interval_s')::int; end if;
  if p_patch ? 'display_order'    then s.display_order    := p_patch->>'display_order'; end if;
  if p_patch ? 'sync_interval_s'  then s.sync_interval_s  := (p_patch->>'sync_interval_s')::int; end if;
  if p_patch ? 'quiet_start'      then s.quiet_start      := (p_patch->>'quiet_start')::time; end if;
  if p_patch ? 'quiet_end'        then s.quiet_end        := (p_patch->>'quiet_end')::time; end if;
  if p_patch ? 'timezone'         then s.timezone         := p_patch->>'timezone'; end if;

  if (s.quiet_start is null) <> (s.quiet_end is null) then
    perform private.fail('quiet_hours_incomplete', 'Set both quiet-hours times, or neither.');
  end if;

  update public.frame_settings set
    image_interval_s = s.image_interval_s, display_order = s.display_order,
    sync_interval_s = s.sync_interval_s, quiet_start = s.quiet_start,
    quiet_end = s.quiet_end, timezone = s.timezone
  where frame_id = p_frame returning * into s;
  return private.settings_json(s);
end;
$$;

-- The owner removes a member, or a member leaves. Their photos stay.
create function public.svc_remove_frame_member(p_user uuid, p_frame uuid, p_target uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  caller_role text;
  target_role text;
begin
  perform private.require_member(p_user);
  if not exists (select 1 from public.frames where id = p_frame) then
    perform private.fail('frame_not_found', 'Frame not found.');
  end if;
  select role into caller_role from public.frame_members where frame_id = p_frame and user_id = p_user;
  if p_target <> p_user and caller_role is distinct from 'owner' then
    perform private.fail('not_allowed', 'Only the frame owner can remove members.');
  end if;
  select role into target_role from public.frame_members where frame_id = p_frame and user_id = p_target;
  if target_role is null then
    perform private.fail('member_not_found', 'Not a member of this frame.');
  end if;
  if target_role = 'owner' then
    perform private.fail('cannot_remove_owner', 'The owner can''t be removed. Delete the frame instead.');
  end if;
  delete from public.frame_members where frame_id = p_frame and user_id = p_target;
end;
$$;

-- ── app-api: invites ──────────────────────────────────────────────────────────

create function public.svc_create_invite(
  p_user uuid, p_frame uuid, p_max_uses int, p_expires_in_s int, p_code_hash text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare inv public.invites;
begin
  if p_frame is null then
    perform private.require_admin(p_user);
  else
    perform private.require_frame_owner(p_user, p_frame);
  end if;
  insert into public.invites (frame_id, created_by, expires_at, max_uses)
    values (p_frame, p_user, now() + make_interval(secs => p_expires_in_s), p_max_uses)
    returning * into inv;
  insert into private.invite_codes (invite_id, code_hash) values (inv.id, p_code_hash);
  return jsonb_build_object('invite_id', inv.id, 'frame_id', inv.frame_id,
    'expires_at', inv.expires_at, 'max_uses', inv.max_uses);
end;
$$;

create function public.svc_revoke_invite(p_user uuid, p_invite uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  inv public.invites;
  caller_role text;
begin
  caller_role := private.require_member(p_user);
  select * into inv from public.invites where id = p_invite;
  if not found then
    perform private.fail('invite_not_found', 'Invite not found.');
  end if;
  if not (inv.created_by = p_user or caller_role = 'admin'
          or (inv.frame_id is not null and exists (
                select 1 from public.frame_members fm
                where fm.frame_id = inv.frame_id and fm.user_id = p_user and fm.role = 'owner'))) then
    perform private.fail('not_allowed', 'You can''t revoke this invite.');
  end if;
  delete from public.invites where id = p_invite;
end;
$$;

-- The one operation that doesn't need an existing membership.
-- Returns {project_role, frame_id}.
create function public.svc_accept_invite(p_user uuid, p_code_hash text, p_display_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  inv public.invites;
  r text;
  changed boolean := false;
begin
  select i.* into inv from public.invites i
    join private.invite_codes c on c.invite_id = i.id
    where c.code_hash = p_code_hash
    for update of i;
  if not found or inv.expires_at < now() or inv.uses >= inv.max_uses then
    perform private.fail('invalid_invite', 'This invite code is not valid.');
  end if;

  select role into r from public.project_members where user_id = p_user;
  if r is null then
    if p_display_name is null then
      perform private.fail('display_name_required', 'A display name is required to join.');
    end if;
    insert into public.project_members (user_id, role, display_name, invited_by)
      values (p_user, 'member', p_display_name, inv.created_by);
    r := 'member';
    changed := true;
  end if;

  if inv.frame_id is not null and not exists (
    select 1 from public.frame_members where frame_id = inv.frame_id and user_id = p_user
  ) then
    insert into public.frame_members (frame_id, user_id, role) values (inv.frame_id, p_user, 'member');
    changed := true;
  end if;

  if changed then
    update public.invites set uses = uses + 1 where id = inv.id;
  end if;
  return jsonb_build_object('project_role', r, 'frame_id', inv.frame_id);
end;
$$;

-- ── app-api: members and account ──────────────────────────────────────────────

-- Admin removes someone: their frames pass to the admin, their photos stay.
-- The auth user is removed by the hourly clean-up.
create function public.svc_remove_project_member(p_user uuid, p_target uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_admin(p_user);
  if p_target = p_user then
    perform private.fail('cannot_remove_self', 'The admin can''t remove themselves. Delete your account instead.');
  end if;
  if not exists (select 1 from public.project_members where user_id = p_target) then
    perform private.fail('member_not_found', 'Not a member of this family space.');
  end if;
  perform private.transfer_frames(p_target, p_user);
  delete from public.project_members where user_id = p_target;
end;
$$;

create function public.svc_update_me(p_user uuid, p_display_name text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare m public.project_members;
begin
  perform private.require_member(p_user);
  update public.project_members set display_name = p_display_name where user_id = p_user returning * into m;
  return jsonb_build_object('user_id', m.user_id, 'display_name', m.display_name, 'role', m.role);
end;
$$;

-- Removes the caller from the space (the function then deletes the auth user).
-- Frames: a member's pass to the admin; the admin's (or all, if there is no admin)
-- are deleted. Photos stay unless p_delete_photos. Returns {storage_paths}.
create function public.svc_delete_me(p_user uuid, p_delete_photos boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  r text;
  admin_id uuid;
  paths text[] := '{}';
  frames uuid[];
  f uuid;
begin
  r := private.require_member(p_user);

  if p_delete_photos then
    with d as (
      delete from public.images where uploaded_by = p_user returning frame_id, storage_path, status
    )
    select coalesce(array_agg(storage_path), '{}'),
           coalesce(array_agg(distinct frame_id) filter (where status = 'ready'), '{}')
      into paths, frames from d;
    perform private.bump_manifest(frames);
  end if;

  select user_id into admin_id from public.project_members where role = 'admin' and user_id <> p_user;
  if r = 'admin' or admin_id is null then
    for f in select frame_id from public.frame_members where user_id = p_user and role = 'owner' loop
      paths := paths || private.delete_frame(f);
    end loop;
  else
    perform private.transfer_frames(p_user, admin_id);
  end if;

  delete from public.project_members where user_id = p_user;
  return jsonb_build_object('storage_paths', to_jsonb(paths));
end;
$$;

-- Returns {project, frames[], users[]} (UsageEntry shape, without free_tier_bytes).
create function public.svc_usage(p_user uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  r text;
  qf public.quota_config;
  qu public.quota_config;
  qp public.quota_config;
begin
  r := private.require_member(p_user);
  select * into qf from public.quota_config where scope = 'frame';
  select * into qu from public.quota_config where scope = 'user';
  select * into qp from public.quota_config where scope = 'project';

  return jsonb_build_object(
    'project', (
      select jsonb_build_object('images', count(*), 'bytes', coalesce(sum(bytes), 0),
        'max_images', qp.max_images, 'max_bytes', qp.max_bytes)
      from public.images),
    'frames', (
      select coalesce(jsonb_agg(jsonb_build_object('frame_id', fm.frame_id,
        'images', (select count(*) from public.images i where i.frame_id = fm.frame_id),
        'bytes', (select coalesce(sum(bytes), 0) from public.images i where i.frame_id = fm.frame_id),
        'max_images', qf.max_images, 'max_bytes', qf.max_bytes)), '[]'::jsonb)
      from public.frame_members fm where fm.user_id = p_user),
    'users', (
      select coalesce(jsonb_agg(jsonb_build_object('user_id', pm.user_id,
        'images', (select count(*) from public.images i where i.uploaded_by = pm.user_id),
        'bytes', (select coalesce(sum(bytes), 0) from public.images i where i.uploaded_by = pm.user_id),
        'max_images', qu.max_images, 'max_bytes', qu.max_bytes)), '[]'::jsonb)
      from public.project_members pm where r = 'admin' or pm.user_id = p_user)
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

-- Now also drops stale pending images; the maintenance sweep removes their objects.
create or replace function private.hourly_cleanup() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from private.pairing_tokens
  where expires_at < now() - interval '1 day' or used_at < now() - interval '1 day';

  delete from public.invites where expires_at < now() or uses >= max_uses;

  delete from public.images where status = 'pending' and created_at < now() - interval '24 hours';

  delete from auth.users u
  where u.created_at < now() - interval '24 hours'
    and not exists (select 1 from public.project_members m where m.user_id = u.id);
end;
$$;

-- ── Privileges ────────────────────────────────────────────────────────────────

revoke execute on all functions in schema private from public, anon;
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on all functions in schema public to service_role;
-- RLS helpers stay callable by authenticated (0002).
grant execute on function
  private.is_project_member(),
  private.is_admin(),
  private.is_frame_member(uuid),
  private.is_frame_owner(uuid),
  private.can_read_frame_object(text)
to authenticated;
