-- Safe zones (geofencing) schema and audit logs.

create extension if not exists "pgcrypto";

create table if not exists public.safe_zones (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  created_by uuid not null references public.users(id) on delete cascade,
  target_user_id uuid references public.users(id) on delete cascade,
  name text not null,
  center_latitude numeric(10,7) not null,
  center_longitude numeric(10,7) not null,
  radius_meters integer not null check (radius_meters > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.safe_zones
  alter column created_by set default auth.uid();

create index if not exists idx_safe_zones_circle on public.safe_zones(circle_id);
create index if not exists idx_safe_zones_target_user on public.safe_zones(target_user_id);
create index if not exists idx_safe_zones_active on public.safe_zones(circle_id, is_active);

create table if not exists public.safe_zone_events (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.safe_zones(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  event_type text not null check (event_type in ('enter', 'exit')),
  event_timestamp timestamptz not null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_safe_zone_events_zone on public.safe_zone_events(zone_id);
create index if not exists idx_safe_zone_events_user_timestamp on public.safe_zone_events(user_id, event_timestamp desc);

alter table public.safe_zones enable row level security;
alter table public.safe_zone_events enable row level security;

create or replace function public.target_in_user_circle(_circle_id uuid, _user_id uuid)
returns boolean
language sql stable as $$
  select exists (
    select 1
    from public.circle_members
    where circle_id = _circle_id
      and user_id = _user_id
      and is_accepted = true
  );
$$;

create or replace function public.safe_zone_event_owner(_zone_id uuid)
returns uuid
language sql stable as $$
  select s.created_by
  from public.safe_zones s
  where s.id = _zone_id;
$$;

create or replace function public.safe_zone_event_access(_zone_id uuid, _viewer uuid)
returns boolean
language sql stable as $$
  select exists (
    select 1
    from public.safe_zones z
    where z.id = _zone_id
      and public.target_in_user_circle(z.circle_id, _viewer)
      and (
        z.target_user_id is null
        or z.target_user_id = _viewer
      )
  );
$$;

drop policy if exists "Members can read safe zones" on public.safe_zones;
drop policy if exists "Members can create safe zones" on public.safe_zones;
drop policy if exists "Members can update own safe zones" on public.safe_zones;
drop policy if exists "Members can delete own safe zones" on public.safe_zones;
drop policy if exists "Members can read safe zone events" on public.safe_zone_events;
drop policy if exists "Users can insert safe zone events" on public.safe_zone_events;

create policy "Members can read safe zones"
  on public.safe_zones for select
  using (
    public.target_in_user_circle(circle_id, auth.uid())
  );

create policy "Members can create safe zones"
  on public.safe_zones for insert
  with check (
    public.target_in_user_circle(circle_id, auth.uid())
    and auth.uid() = created_by
  );

create policy "Members can update own safe zones"
  on public.safe_zones for update
  using (auth.uid() = created_by)
  with check (auth.uid() = created_by);

create policy "Members can delete own safe zones"
  on public.safe_zones for delete
  using (auth.uid() = created_by);

create policy "Members can read safe zone events"
  on public.safe_zone_events for select
  using (
    public.safe_zone_event_access(zone_id, auth.uid())
  );

create policy "Users can insert safe zone events"
  on public.safe_zone_events for insert
  with check (
    user_id = auth.uid()
    and public.safe_zone_event_access(zone_id, auth.uid())
  );

create or replace function public.notify_safe_zone_event()
returns trigger
language plpgsql as $function$
begin
  perform pg_notify(
    'safe_zone_events',
    json_build_object(
      'event_id', NEW.id,
      'zone_id', NEW.zone_id,
      'user_id', NEW.user_id,
      'event_type', NEW.event_type,
      'event_timestamp', NEW.event_timestamp
    )::text
  );
  return new;
end;
$function$;

drop trigger if exists trg_safe_zone_events_notify on public.safe_zone_events;
create trigger trg_safe_zone_events_notify
  after insert on public.safe_zone_events
  for each row
  execute function public.notify_safe_zone_event();

comment on function public.notify_safe_zone_event() is 'Prepared hook for push notifications. Replace pg_notify target with your server-side worker/webhook.';
