-- Location history retention and cleanup helpers.

alter table public.location_sharing_settings
  add column if not exists history_retention_hours integer not null default 24;

update public.location_sharing_settings
set history_retention_hours = 24
where history_retention_hours is null;

alter table public.location_sharing_settings
  alter column history_retention_hours set default 24;

comment on column public.location_sharing_settings.history_retention_hours is 'Member history retention hours; default 24h for free plan. Store premium can set 168 (7d) or 720 (30d).';

create or replace function public.delete_expired_location_updates()
returns integer
language plpgsql
security definer as $function$
declare
  deleted_count integer;
begin
  delete from public.location_updates lu
  where lu.created_at < (
    select timezone('utc', now()) - make_interval(hours => coalesce(s.history_retention_hours, 24))
    from public.location_sharing_settings s
    where s.user_id = lu.user_id
  );

  get diagnostics deleted_count = row_count;
  return deleted_count;
end;
$function$;

comment on function public.delete_expired_location_updates() is
'Delete location_updates older than each user configured retention period from location_sharing_settings.';

-- Optional scheduling (run hourly with pg_cron on environments where extension is available):
-- select cron.schedule(''safe_circle_cleanup_locations'', ''0 * * * *'', ''select public.delete_expired_location_updates();'');
