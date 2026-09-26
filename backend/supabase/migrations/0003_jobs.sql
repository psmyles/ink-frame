-- 0003: scheduled jobs (PLAN.md §7.5).
-- Pure-database clean-up runs in SQL. Deleting storage objects needs the Storage API
-- (Supabase blocks deleting storage.objects with SQL), so pg_net calls
-- app-api /internal/maintenance with a secret that only the database and the
-- service role can read.

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- key/value settings for server-side code. project_url is written by the migration
-- runner after every run (the database doesn't know its own public URL).
create table private.config (
  key   text primary key,
  value text not null
);
insert into private.config (key, value)
values ('maintenance_secret', encode(extensions.gen_random_bytes(32), 'hex'));

create function private.hourly_cleanup() returns void
language plpgsql security definer set search_path = '' as $$
begin
  delete from private.pairing_tokens
  where expires_at < now() - interval '1 day' or used_at < now() - interval '1 day';

  delete from public.invites where expires_at < now() or uses >= max_uses;

  -- Their objects are removed by the maintenance sweep.
  delete from public.images where status = 'pending' and created_at < now() - interval '24 hours';

  -- Auth users who never joined, or who left. Signing up is open at the auth layer
  -- (PLAN.md §5.4); membership is what matters.
  delete from auth.users u
  where u.created_at < now() - interval '24 hours'
    and not exists (select 1 from public.members m where m.user_id = u.id);
end;
$$;

create function private.request_maintenance() returns void
language plpgsql security definer set search_path = '' as $$
declare
  base   text := (select value from private.config where key = 'project_url');
  secret text := (select value from private.config where key = 'maintenance_secret');
begin
  if base is null then
    return;
  end if;
  perform net.http_post(
    url     := base || '/functions/v1/app-api/internal/maintenance',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-maintenance-secret', secret),
    body    := '{}'::jsonb
  );
end;
$$;

revoke execute on function private.hourly_cleanup(), private.request_maintenance() from public, anon, authenticated;

select cron.schedule('inkframe-hourly-cleanup', '7 * * * *', 'select private.hourly_cleanup()');
select cron.schedule('inkframe-hourly-maintenance', '17 * * * *', 'select private.request_maintenance()');
