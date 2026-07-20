-- Background sharing settings + missing location telemetry columns

-- Backward-compatible columns for location sharing controls.
alter table public.location_sharing_settings
  add column if not exists is_background_sharing_enabled boolean not null default false,
  add column if not exists update_interval_seconds integer not null default 30,
  add column if not exists distance_filter_meters integer not null default 30,
  add column if not exists is_battery_saving_mode boolean not null default false;

alter table public.location_sharing_settings
  alter column update_interval_seconds set default 30,
  alter column distance_filter_meters set default 30;

update public.location_sharing_settings
set is_background_sharing_enabled = false
where is_background_sharing_enabled is null;

update public.location_sharing_settings
set update_interval_seconds = 30
where update_interval_seconds is null;

update public.location_sharing_settings
set distance_filter_meters = 30
where distance_filter_meters is null;

update public.location_sharing_settings
set is_battery_saving_mode = false
where is_battery_saving_mode is null;

-- Add fields required for live location sharing telemetry.
alter table public.location_updates
  add column if not exists accuracy_meters numeric,
  add column if not exists speed_mps numeric,
  add column if not exists heading_degrees numeric,
  add column if not exists battery_level numeric;

comment on column public.location_updates.accuracy_meters is 'Horizontal accuracy in meters at upload time';
comment on column public.location_updates.speed_mps is 'Speed in meters per second at upload time';
comment on column public.location_updates.heading_degrees is 'Direction in degrees at upload time';
comment on column public.location_updates.battery_level is 'Battery percentage at upload time, if available';

update public.location_updates
set created_at = timezone('utc', now())
where created_at is null;

alter table public.location_updates
  alter column created_at set default timezone('utc', now());
