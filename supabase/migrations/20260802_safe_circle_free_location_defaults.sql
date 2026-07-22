-- Keep the database default aligned with the free-plan battery guard and the
-- Flutter model fallback.
alter table public.location_sharing_settings
  alter column distance_filter_meters set default 100;

