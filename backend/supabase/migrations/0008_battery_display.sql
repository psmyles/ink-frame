-- How the frame shows its battery over a photo (shared/api/openapi.yaml 2.3.0): `bar`,
-- a thin line along the bottom, or `number`, a small percentage in the bottom-left
-- corner. The owner picks it; it reaches the hardware with the other settings in /sync,
-- so changing it makes the frame "Changes waiting".

alter table public.frame
  add column battery_display text not null default 'bar' check (battery_display in ('bar', 'number'));

-- Returns {manifest_version, settings (with IANA timezone), images?}.
-- images (with storage_path) is null when p_manifest_version is current.
create or replace function public.svc_sync_frame(
  p_secret_hash text, p_manifest_version bigint, p_fw_version text,
  p_battery_pct int, p_rssi int, p_sd_total_bytes bigint, p_sd_free_bytes bigint, p_cache_bytes bigint
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
    last_seen_at = now(), fw_version = p_fw_version, battery_pct = p_battery_pct, rssi = p_rssi,
    sd_total_bytes = p_sd_total_bytes, sd_free_bytes = p_sd_free_bytes, cache_bytes = p_cache_bytes,
    synced_manifest_version = manifest_version
  where true
  returning * into f;

  return jsonb_build_object(
    'manifest_version', f.manifest_version,
    'settings', jsonb_build_object(
      'image_interval_s', f.image_interval_s, 'display_order', f.display_order,
      'sync_interval_s', f.sync_interval_s,
      'quiet_start', to_char(f.quiet_start, 'HH24:MI'), 'quiet_end', to_char(f.quiet_end, 'HH24:MI'),
      'timezone', f.timezone, 'battery_display', f.battery_display),
    'images', case when p_manifest_version = f.manifest_version then null else (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', i.id, 'sha256', i.sha256, 'bytes', i.bytes, 'position', i.position,
        'storage_path', i.storage_path) order by i.position), '[]'::jsonb)
      from public.images i where i.status = 'ready'
    ) end
  );
end;
$$;

create or replace function private.frame_json(f public.frame) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'id', f.id, 'name', f.name, 'model_id', f.model_id, 'connected', f.hw_id is not null,
    'up_to_date', f.up_to_date, 'fw_version', f.fw_version, 'last_seen_at', f.last_seen_at, 'battery_pct', f.battery_pct,
    'sd_total_bytes', f.sd_total_bytes, 'sd_free_bytes', f.sd_free_bytes, 'cache_bytes', f.cache_bytes,
    'image_interval_s', f.image_interval_s, 'display_order', f.display_order,
    'sync_interval_s', f.sync_interval_s,
    'quiet_start', to_char(f.quiet_start, 'HH24:MI'), 'quiet_end', to_char(f.quiet_end, 'HH24:MI'),
    'timezone', f.timezone, 'low_battery_pct', f.low_battery_pct, 'battery_display', f.battery_display
  );
$$;

create or replace function public.svc_update_frame_settings(p_user uuid, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  f public.frame;
  device_settings boolean := p_patch ?| array['image_interval_s', 'display_order', 'sync_interval_s',
                                               'quiet_start', 'quiet_end', 'timezone', 'battery_display'];
begin
  perform private.require_owner(p_user);
  select * into f from public.frame for update;

  if p_patch ? 'image_interval_s' then f.image_interval_s := (p_patch->>'image_interval_s')::int; end if;
  if p_patch ? 'display_order'    then f.display_order    := p_patch->>'display_order'; end if;
  if p_patch ? 'sync_interval_s'  then f.sync_interval_s  := (p_patch->>'sync_interval_s')::int; end if;
  if p_patch ? 'quiet_start'      then f.quiet_start      := (p_patch->>'quiet_start')::time; end if;
  if p_patch ? 'quiet_end'        then f.quiet_end        := (p_patch->>'quiet_end')::time; end if;
  if p_patch ? 'timezone'         then f.timezone         := p_patch->>'timezone'; end if;
  if p_patch ? 'low_battery_pct'  then f.low_battery_pct  := (p_patch->>'low_battery_pct')::smallint; end if;
  if p_patch ? 'battery_display'  then f.battery_display  := p_patch->>'battery_display'; end if;

  if (f.quiet_start is null) <> (f.quiet_end is null) then
    perform private.fail('quiet_hours_incomplete', 'Set both quiet-hours times, or neither.');
  end if;

  update public.frame set
    image_interval_s = f.image_interval_s, display_order = f.display_order,
    sync_interval_s = f.sync_interval_s, quiet_start = f.quiet_start,
    quiet_end = f.quiet_end, timezone = f.timezone, low_battery_pct = f.low_battery_pct,
    battery_display = f.battery_display,
    settings_updated_at = case when device_settings then now() else settings_updated_at end
  where true
  returning * into f;
  return private.frame_json(f);
end;
$$;
