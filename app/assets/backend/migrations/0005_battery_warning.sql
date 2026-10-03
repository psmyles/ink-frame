-- Low-battery warning (PLAN.md §15, app-flow §4.3): the owner picks a level; the
-- app warns when the frame's battery_pct drops below it. App-only: the hardware
-- never gets it, so changing only this doesn't touch settings_updated_at (the frame
-- stays "Up to date").

alter table public.frame
  add column low_battery_pct smallint default 20 check (low_battery_pct between 5 and 50);

create or replace function private.frame_json(f public.frame) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'id', f.id, 'name', f.name, 'model_id', f.model_id, 'connected', f.hw_id is not null,
    'up_to_date', f.up_to_date, 'fw_version', f.fw_version, 'last_seen_at', f.last_seen_at, 'battery_pct', f.battery_pct,
    'image_interval_s', f.image_interval_s, 'display_order', f.display_order,
    'sync_interval_s', f.sync_interval_s,
    'quiet_start', to_char(f.quiet_start, 'HH24:MI'), 'quiet_end', to_char(f.quiet_end, 'HH24:MI'),
    'timezone', f.timezone, 'low_battery_pct', f.low_battery_pct
  );
$$;

create or replace function public.svc_update_frame_settings(p_user uuid, p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  f public.frame;
  device_settings boolean := p_patch ?| array['image_interval_s', 'display_order', 'sync_interval_s',
                                               'quiet_start', 'quiet_end', 'timezone'];
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

  if (f.quiet_start is null) <> (f.quiet_end is null) then
    perform private.fail('quiet_hours_incomplete', 'Set both quiet-hours times, or neither.');
  end if;

  update public.frame set
    image_interval_s = f.image_interval_s, display_order = f.display_order,
    sync_interval_s = f.sync_interval_s, quiet_start = f.quiet_start,
    quiet_end = f.quiet_end, timezone = f.timezone, low_battery_pct = f.low_battery_pct,
    settings_updated_at = case when device_settings then now() else settings_updated_at end
  where true
  returning * into f;
  return private.frame_json(f);
end;
$$;
