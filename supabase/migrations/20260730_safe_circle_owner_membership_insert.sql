-- A new circle cannot already have an owner membership. Avoid UPSERT here:
-- Postgres requires SELECT/UPDATE RLS for ON CONFLICT, but membership SELECT
-- intentionally becomes available only after this first accepted row exists.
create or replace function public.sync_owner_membership()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  insert into public.circle_members(circle_id, user_id, role, is_accepted, invited_at)
  values (NEW.id, NEW.owner_id, 'owner', true, timezone('utc', now()));
  return NEW;
end;
$function$;

revoke execute on function public.sync_owner_membership() from public, anon, authenticated;

