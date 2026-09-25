-- 0005: owner-only actions answer not_frame_owner to anyone who isn't the owner,
-- including project members who aren't on the frame (contract: NotFrameOwner).

create or replace function private.require_frame_owner(p_user uuid, p_frame uuid) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_member(p_user);
  if not exists (select 1 from public.frames where id = p_frame) then
    perform private.fail('frame_not_found', 'Frame not found.');
  end if;
  if not exists (
    select 1 from public.frame_members
    where frame_id = p_frame and user_id = p_user and role = 'owner'
  ) then
    perform private.fail('not_frame_owner', 'Only the frame owner can do this.');
  end if;
end;
$$;
