-- Read-only watch tokens for the low-battery notification (PLAN.md §15): a phone's
-- background check reads the frame's battery with its own token, never with the
-- person's session (refresh tokens rotate; reusing an old one signs them out). One
-- token per device and person; gone when they leave the frame or delete their account.

create table private.watch_tokens (
  token_hash   text primary key check (token_hash ~ '^[0-9a-f]{64}$'),
  user_id      uuid not null references public.members (user_id) on delete cascade,
  created_at   timestamptz not null default now(),
  last_used_at timestamptz
);
create index watch_tokens_user on private.watch_tokens (user_id, created_at);

-- A member's new token; their 10 newest are kept.
create function public.svc_create_watch_token(p_user uuid, p_token_hash text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_member(p_user);
  insert into private.watch_tokens (token_hash, user_id) values (p_token_hash, p_user);
  delete from private.watch_tokens
  where user_id = p_user
    and token_hash not in (
      select token_hash from private.watch_tokens where user_id = p_user order by created_at desc limit 10
    );
end;
$$;

-- What the notification needs, for a valid token.
create function public.svc_watch_frame(p_token_hash text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare f public.frame;
begin
  update private.watch_tokens set last_used_at = now() where token_hash = p_token_hash;
  if not found then
    perform private.fail('invalid_watch_token', 'Unknown or revoked watch token.');
  end if;
  select * into f from public.frame;
  return jsonb_build_object(
    'name', f.name, 'connected', f.hw_id is not null, 'battery_pct', f.battery_pct,
    'low_battery_pct', f.low_battery_pct, 'last_seen_at', f.last_seen_at, 'sync_interval_s', f.sync_interval_s
  );
end;
$$;

create function public.svc_revoke_watch_token(p_token_hash text) returns void
language sql security definer set search_path = '' as $$
  delete from private.watch_tokens where token_hash = p_token_hash;
$$;

revoke execute on function public.svc_create_watch_token(uuid, text), public.svc_watch_frame(text),
  public.svc_revoke_watch_token(text) from public, anon, authenticated;
grant execute on function public.svc_create_watch_token(uuid, text), public.svc_watch_frame(text),
  public.svc_revoke_watch_token(text) to service_role;
