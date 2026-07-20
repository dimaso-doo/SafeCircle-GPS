-- SOS + notification preferences + push token registry.
-- This migration is store-compliant by keeping push tokens and alert records user-scoped
-- and membership-scoped, with explicit user opt-in checks on delivery.

create extension if not exists "pgcrypto";

create table if not exists public.notification_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  push_enabled boolean not null default true,
  notify_sos boolean not null default true,
  notify_safe_zone_enter boolean not null default true,
  notify_safe_zone_exit boolean not null default true,
  notify_sharing_paused boolean not null default true,
  updated_at timestamptz not null default timezone('utc', now()),
  unique (user_id)
);

create table if not exists public.notification_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('android', 'ios', 'web')),
  app_version text,
  is_active boolean not null default true,
  last_seen_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (user_id, token)
);

create table if not exists public.sos_events (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  latitude numeric(10,7) not null,
  longitude numeric(10,7) not null,
  accuracy_meters numeric,
  speed_mps numeric,
  heading_degrees numeric,
  battery_level numeric,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_notification_settings_user on public.notification_settings(user_id);
create index if not exists idx_notification_tokens_user on public.notification_tokens(user_id);
create index if not exists idx_notification_tokens_is_active on public.notification_tokens(is_active);
create index if not exists idx_sos_events_circle_created on public.sos_events(circle_id, created_at desc);
create index if not exists idx_sos_events_user_created on public.sos_events(user_id, created_at desc);

alter table public.notification_settings enable row level security;
alter table public.notification_tokens enable row level security;
alter table public.sos_events enable row level security;

drop policy if exists "Users can read own notification settings" on public.notification_settings;
drop policy if exists "Users can insert own notification settings" on public.notification_settings;
drop policy if exists "Users can update own notification settings" on public.notification_settings;

drop policy if exists "Users can read own notification tokens" on public.notification_tokens;
drop policy if exists "Users can insert own notification tokens" on public.notification_tokens;
drop policy if exists "Users can update own notification tokens" on public.notification_tokens;
drop policy if exists "Users can delete own notification tokens" on public.notification_tokens;

drop policy if exists "Users can read sos events in circles" on public.sos_events;
drop policy if exists "Users can insert own sos events" on public.sos_events;

create policy "Users can read own notification settings"
  on public.notification_settings for select
  using (auth.uid() = user_id);

create policy "Users can insert own notification settings"
  on public.notification_settings for insert
  with check (auth.uid() = user_id);

create policy "Users can update own notification settings"
  on public.notification_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can read own notification tokens"
  on public.notification_tokens for select
  using (auth.uid() = user_id);

create policy "Users can insert own notification tokens"
  on public.notification_tokens for insert
  with check (auth.uid() = user_id);

create policy "Users can update own notification tokens"
  on public.notification_tokens for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own notification tokens"
  on public.notification_tokens for delete
  using (auth.uid() = user_id);

create policy "Users can read sos events in circles"
  on public.sos_events for select
  using (
    public.target_in_user_circle(circle_id, auth.uid())
  );

create policy "Users can insert own sos events"
  on public.sos_events for insert
  with check (
    user_id = auth.uid()
    and public.target_in_user_circle(circle_id, auth.uid())
  );

create or replace function public.touch_notification_metadata_updated_at()
returns trigger
language plpgsql as $function$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$function$;

drop trigger if exists trg_notification_settings_updated_at on public.notification_settings;
create trigger trg_notification_settings_updated_at
  before update on public.notification_settings
  for each row
  execute function public.touch_notification_metadata_updated_at();

create or replace function public.touch_notification_token_seen_at()
returns trigger
language plpgsql as $function$
begin
  new.updated_at = timezone('utc', now());
  new.last_seen_at = timezone('utc', now());
  return new;
end;
$function$;

drop trigger if exists trg_notification_tokens_seen on public.notification_tokens;
create trigger trg_notification_tokens_seen
  before update on public.notification_tokens
  for each row
  execute function public.touch_notification_token_seen_at();

-- A light helper to preload preferences in places where a consumer wants a direct
-- yes/no for each notification type.
create or replace function public.notification_preference_enabled(
  p_user_id uuid,
  p_type text
)
returns boolean
language plpgsql stable as $function$
declare
  v_settings record;
begin
  select ns.push_enabled, ns.notify_sos, ns.notify_safe_zone_enter, ns.notify_safe_zone_exit, ns.notify_sharing_paused
    into v_settings
  from public.notification_settings ns
  where ns.user_id = p_user_id;

  if v_settings is null then
    return true;
  end if;

  if not v_settings.push_enabled then
    return false;
  end if;

  case p_type
    when 'sosAlert' then return v_settings.notify_sos;
    when 'safeZoneEnter' then return v_settings.notify_safe_zone_enter;
    when 'safeZoneExit' then return v_settings.notify_safe_zone_exit;
    when 'sharingPaused' then return v_settings.notify_sharing_paused;
    else return false;
  end case;
end;
$function$;

comment on function public.notification_preference_enabled is
  'Return whether notification type should be delivered for a specific user.';

comment on table public.notification_settings is 'Per-user notification preferences for push delivery.';
comment on table public.notification_tokens is 'FCM device token registry for signed-in users.';
comment on table public.sos_events is 'Stores SOS alerts with location at the moment the button is pressed.';
