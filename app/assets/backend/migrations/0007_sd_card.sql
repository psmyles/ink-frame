-- The frame's memory card (shared/api/openapi.yaml 2.2.0): /sync also reports the
-- card's size and what the frame's own photo cache takes, so the app can show the card
-- and warn when the photos don't all fit (sd_free_bytes + cache_bytes - 8 MB).

alter table public.frame
  add column sd_total_bytes bigint check (sd_total_bytes >= 0),
  add column cache_bytes bigint check (cache_bytes >= 0);

drop function public.svc_sync_frame(text, bigint, text, int, int, bigint);

-- Returns {manifest_version, settings (with IANA timezone), images?}.
-- images (with storage_path) is null when p_manifest_version is current.
create function public.svc_sync_frame(
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

-- Tombstones the connected device's secret (it gets 410) and forgets the hardware.
create or replace function private.disconnect() returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into private.removed_devices (secret_hash)
    select secret_hash from private.frame_secret on conflict do nothing;
  delete from private.frame_secret where true;
  update public.frame set hw_id = null, fw_version = null, last_seen_at = null,
    battery_pct = null, rssi = null, sd_total_bytes = null, sd_free_bytes = null, cache_bytes = null,
    synced_manifest_version = null where true;
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
    'timezone', f.timezone, 'low_battery_pct', f.low_battery_pct
  );
$$;

revoke execute on function public.svc_sync_frame(text, bigint, text, int, int, bigint, bigint, bigint)
  from public, anon, authenticated;
grant execute on function public.svc_sync_frame(text, bigint, text, int, int, bigint, bigint, bigint) to service_role;
revoke execute on function private.disconnect(), private.frame_json(public.frame) from public, anon;
