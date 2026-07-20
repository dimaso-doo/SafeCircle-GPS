-- Add battery level to live location updates and ensure timestamps are explicit

alter table public.location_updates
  add column if not exists battery_level numeric;

comment on column public.location_updates.battery_level is 'Battery percentage at upload time, if available';

update public.location_updates
set created_at = timezone('utc', now())
where created_at is null;

alter table public.location_updates
  alter column created_at set default timezone('utc', now());
