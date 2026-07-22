-- SafeCircle subscriptions + plan-based limits and gating

create extension if not exists "pgcrypto";

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  max_circles integer not null default 1,
  max_members_per_circle integer not null default 2,
  max_history_retention_hours integer not null default 24,
  allow_safe_zones boolean not null default false,
  allow_sos boolean not null default false,
  allow_priority_updates boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.user_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id) on delete restrict,
  status text not null default 'active',
  started_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  platform_customer_id text,
  platform_purchase_id text,
  metadata jsonb,
  constraint user_subscriptions_status_chk check (status in ('active', 'trialing', 'paused', 'canceled', 'expired', 'past_due')),
  unique (user_id)
);

insert into public.subscription_plans (
  slug,
  name,
  max_circles,
  max_members_per_circle,
  max_history_retention_hours,
  allow_safe_zones,
  allow_sos,
  allow_priority_updates
) values
  (
    'free',
    'Free',
    1,
    2,
    24,
    false,
    false,
    false
  ),
  (
    'premium',
    'Premium',
    10,
    20,
    720,
    true,
    true,
    true
  )
on conflict (slug) do update
set
  max_circles = excluded.max_circles,
  max_members_per_circle = excluded.max_members_per_circle,
  max_history_retention_hours = excluded.max_history_retention_hours,
  allow_safe_zones = excluded.allow_safe_zones,
  allow_sos = excluded.allow_sos,
  allow_priority_updates = excluded.allow_priority_updates,
  name = excluded.name,
  updated_at = timezone('utc', now());

create or replace function public.get_subscription_plan(
  p_user_id uuid
)
returns public.subscription_plans
language sql stable as $function$
  select p.*
  from public.subscription_plans p
  where p.id = coalesce(
    (
      select s.plan_id
      from public.user_subscriptions s
      where s.user_id = p_user_id
        and s.status in ('active', 'trialing')
        and (s.expires_at is null or s.expires_at > timezone('utc', now()))
      order by s.started_at desc
      limit 1
    ),
    (select id from public.subscription_plans where slug = 'free' limit 1)
  )
  limit 1;
$function$;

create or replace function public.user_subscription_limits(
  p_user_id uuid
)
returns table(
  plan_slug text,
  plan_name text,
  max_circles integer,
  max_members_per_circle integer,
  max_history_retention_hours integer,
  allow_safe_zones boolean,
  allow_sos boolean,
  allow_priority_updates boolean
)
language sql stable as $function$
  select
    p.slug,
    p.name,
    p.max_circles,
    p.max_members_per_circle,
    p.max_history_retention_hours,
    p.allow_safe_zones,
    p.allow_sos,
    p.allow_priority_updates
  from public.get_subscription_plan(p_user_id) as p;
$function$;

create or replace function public.user_allows_feature(
  p_user_id uuid,
  p_feature text
)
returns boolean
language plpgsql stable as $function$
  declare
    v_limits record;
  begin
    select * into v_limits from public.user_subscription_limits(p_user_id);

    return case p_feature
      when 'safe_zones' then v_limits.allow_safe_zones
      when 'sos' then v_limits.allow_sos
      when 'priority_updates' then v_limits.allow_priority_updates
      else false
    end;
  exception
    when no_data_found then
      return false;
  end;
$function$;

create or replace function public.touch_subscription_updated_at()
returns trigger
language plpgsql as $function$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$function$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer as $function$
  declare
    v_free_plan_id uuid;
    v_display_name text;
  begin
    v_display_name := coalesce(
      new.raw_user_meta_data->>'display_name',
      split_part(new.email, '@', 1)
    );

    insert into public.users (id, display_name)
    values (new.id, v_display_name)
    on conflict (id) do nothing;

    select id into v_free_plan_id
    from public.subscription_plans
    where slug = 'free'
    limit 1;

    if v_free_plan_id is not null then
      insert into public.user_subscriptions (
        user_id,
        plan_id,
        status,
        started_at
      )
      values (new.id, v_free_plan_id, 'active', timezone('utc', now()))
      on conflict (user_id) do nothing;
    end if;

    return new;
  end;
$function$;

create or replace function public.touch_timestamp_updated_at()
returns trigger
language plpgsql as $function$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$function$;

create or replace function public.enforce_circle_creation_limit()
returns trigger
language plpgsql as $function$
  declare
    v_limits record;
    v_count int;
  begin
    select * into v_limits from public.user_subscription_limits(NEW.owner_id);
    select count(*) into v_count
    from public.circle_members
    where user_id = NEW.owner_id
      and is_accepted = true;

    if v_count >= v_limits.max_circles then
      raise exception 'Your plan allows % active circle(s). Upgrade to Premium for more.', v_limits.max_circles;
    end if;

    return NEW;
  end;
$function$;

create or replace function public.enforce_circle_membership_limit()
returns trigger
language plpgsql as $function$
  declare
    v_limits record;
    v_circle_count int;
    v_user_count int;
  begin
    if not NEW.is_accepted then
      return NEW;
    end if;

    select * into v_limits from public.user_subscription_limits(NEW.user_id);

    select count(*) into v_circle_count
    from public.circle_members
    where circle_id = NEW.circle_id
      and is_accepted = true;

    if v_circle_count >= v_limits.max_members_per_circle then
      raise exception 'Your current plan allows % accepted members per circle.', v_limits.max_members_per_circle;
    end if;

    select count(*) into v_user_count
    from public.circle_members cm
    where cm.user_id = NEW.user_id
      and cm.is_accepted = true;

    if v_user_count >= v_limits.max_circles then
      raise exception 'Your current plan allows % active circles.', v_limits.max_circles;
    end if;

    return NEW;
  end;
$function$;

create or replace function public.enforce_location_sharing_settings_limit()
returns trigger
language plpgsql as $function$
  declare
    v_limits record;
  begin
    select * into v_limits from public.user_subscription_limits(NEW.user_id);

    if NEW.history_retention_hours is null or NEW.history_retention_hours < 24 then
      NEW.history_retention_hours = 24;
    end if;

    if NEW.history_retention_hours > v_limits.max_history_retention_hours then
      raise exception 'History retention cannot exceed % hours for your current plan.',
        v_limits.max_history_retention_hours;
    end if;

    if not public.user_allows_feature(NEW.user_id, 'priority_updates') then
      if NEW.update_interval_seconds < 30 then
        raise exception 'Free plan requires at least 30s update interval. Upgrade to Premium for priority updates.';
      end if;
      if NEW.distance_filter_meters < 100 then
        raise exception 'Free plan requires at least 100m distance filter. Upgrade to Premium for priority updates.';
      end if;
    end if;

    return NEW;
  end;
$function$;

alter table public.subscription_plans enable row level security;
alter table public.user_subscriptions enable row level security;

drop policy if exists "Subscription plans are public" on public.subscription_plans;
drop policy if exists "Users can read own subscription" on public.user_subscriptions;
drop policy if exists "Users can insert their own subscription" on public.user_subscriptions;
drop policy if exists "Users can update own subscription" on public.user_subscriptions;

create policy "Subscription plans are public"
  on public.subscription_plans for select
  using (true);

create policy "Users can read own subscription"
  on public.user_subscriptions for select
  using (auth.uid() = user_id);

drop trigger if exists trg_auth_user_created on auth.users;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute procedure public.handle_new_user();

drop trigger if exists trg_circles_plan_limit on public.circles;
drop trigger if exists trg_circle_members_plan_limit_insert on public.circle_members;
drop trigger if exists trg_circle_members_plan_limit_update on public.circle_members;
drop trigger if exists trg_location_sharing_settings_plan_limits on public.location_sharing_settings;

drop trigger if exists trg_subscription_plans_touch_updated_at on public.subscription_plans;
drop trigger if exists trg_user_subscriptions_touch_updated_at on public.user_subscriptions;
drop trigger if exists trg_subscription_plan_updated_at on public.subscription_plans;

drop function if exists public.touch_subscription_updated_at();

create trigger trg_subscription_plans_touch_updated_at
  before update on public.subscription_plans
  for each row
  execute function public.touch_timestamp_updated_at();

create trigger trg_user_subscriptions_touch_updated_at
  before update on public.user_subscriptions
  for each row
  execute function public.touch_timestamp_updated_at();

create trigger trg_circles_plan_limit
  before insert on public.circles
  for each row
  execute function public.enforce_circle_creation_limit();

create trigger trg_circle_members_plan_limit_insert
  before insert on public.circle_members
  for each row
  when (new.is_accepted = true)
  execute function public.enforce_circle_membership_limit();

create trigger trg_circle_members_plan_limit_update
  before update of is_accepted on public.circle_members
  for each row
  when (new.is_accepted = true and old.is_accepted is distinct from true)
  execute function public.enforce_circle_membership_limit();

create trigger trg_location_sharing_settings_plan_limits
  before insert or update of history_retention_hours, update_interval_seconds, distance_filter_meters
  on public.location_sharing_settings
  for each row
  execute function public.enforce_location_sharing_settings_limit();

-- Ensure plan-based feature checks on feature-heavy writes.

drop policy if exists "Members can create safe zones" on public.safe_zones;
drop policy if exists "Members can update own safe zones" on public.safe_zones;
drop policy if exists "Members can delete own safe zones" on public.safe_zones;
drop policy if exists "Users can insert own sos events" on public.sos_events;

drop policy if exists "Users can update own sharing settings" on public.location_sharing_settings;
drop policy if exists "Users can upsert own sharing settings" on public.location_sharing_settings;
drop policy if exists "Users can modify own sharing settings" on public.location_sharing_settings;

create policy "Members can create safe zones"
  on public.safe_zones for insert
  with check (
    public.target_in_user_circle(circle_id, auth.uid())
    and auth.uid() = created_by
    and public.user_allows_feature(auth.uid(), 'safe_zones')
  );

create policy "Members can update own safe zones"
  on public.safe_zones for update
  using (
    auth.uid() = created_by
    and public.user_allows_feature(auth.uid(), 'safe_zones')
  )
  with check (
    auth.uid() = created_by
    and public.user_allows_feature(auth.uid(), 'safe_zones')
  );

create policy "Members can delete own safe zones"
  on public.safe_zones for delete
  using (
    auth.uid() = created_by
    and public.user_allows_feature(auth.uid(), 'safe_zones')
  );

create policy "Users can insert own sos events"
  on public.sos_events for insert
  with check (
    user_id = auth.uid()
    and public.target_in_user_circle(circle_id, auth.uid())
    and public.user_allows_feature(auth.uid(), 'sos')
  );

comment on function public.get_subscription_plan is 'Resolve the current effective subscription plan for a user with free fallback.';
comment on function public.user_subscription_limits is 'Expose plan limits and entitlements for runtime feature gating.';
comment on function public.user_allows_feature is 'Boolean check for plan feature flags (safe_zones/sos/priority_updates).';
comment on function public.enforce_circle_creation_limit is 'Server-side guard for free-tier circle-count limitations.';
comment on function public.enforce_circle_membership_limit is 'Server-side guard for plan-based per-circle and per-user membership limits.';
comment on function public.enforce_location_sharing_settings_limit is 'Enforces retention and free-tier live-location defaults from subscription plan limits.';

insert into public.user_subscriptions (user_id, plan_id, status, started_at)
select u.id, p.id, 'active', timezone('utc', now())
from public.users u
cross join public.subscription_plans p
where p.slug = 'free'
  and not exists (
    select 1 from public.user_subscriptions us where us.user_id = u.id
  )
on conflict (user_id) do nothing;
