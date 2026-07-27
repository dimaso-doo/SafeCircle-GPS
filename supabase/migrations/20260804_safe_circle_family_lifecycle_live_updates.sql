-- Family lifecycle controls and practical live-location defaults.

-- Users may own or join several private families in the MVP. Premium can
-- still gate extended history, safe zones and priority/background features.
update public.subscription_plans
set
  max_circles = 5,
  max_members_per_circle = 10,
  updated_at = timezone('utc', now())
where slug = 'free';

alter table public.location_sharing_settings
  alter column update_interval_seconds set default 10,
  alter column distance_filter_meters set default 10;

update public.location_sharing_settings
set update_interval_seconds = 10
where update_interval_seconds = 30;

update public.location_sharing_settings
set distance_filter_meters = 10
where distance_filter_meters = 100;

create or replace function public.enforce_location_sharing_settings_limit()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_limits record;
begin
  select *
  into v_limits
  from public.user_subscription_limits(NEW.user_id);

  if NEW.history_retention_hours is null
     or NEW.history_retention_hours < 24 then
    NEW.history_retention_hours = 24;
  end if;

  if NEW.history_retention_hours > v_limits.max_history_retention_hours then
    raise exception
      'History retention cannot exceed % hours for your current plan.',
      v_limits.max_history_retention_hours;
  end if;

  if NEW.update_interval_seconds < 10 then
    raise exception 'Location update interval cannot be under 10 seconds.';
  end if;

  if NEW.distance_filter_meters < 10 then
    raise exception 'Location distance filter cannot be under 10 meters.';
  end if;

  return NEW;
end;
$function$;

-- Only legitimate owner membership rows can be inserted directly. Invite
-- joins continue through the guarded join_circle_by_invite_code RPC.
drop policy if exists "Users can add memberships"
  on public.circle_members;
create policy "Owners can add their owner membership"
  on public.circle_members for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and role = 'owner'
    and is_accepted = true
    and exists (
      select 1
      from public.circles c
      where c.id = circle_id
        and c.owner_id = (select auth.uid())
    )
  );

drop policy if exists "Owners can delete own circles"
  on public.circles;
create policy "Owners can delete own circles"
  on public.circles for delete
  to authenticated
  using (owner_id = (select auth.uid()));

drop policy if exists "Members can leave circles"
  on public.circle_members;
create policy "Members can leave circles"
  on public.circle_members for delete
  to authenticated
  using (
    user_id = (select auth.uid())
    and role <> 'owner'
  );

drop policy if exists "Owners can remove circle members"
  on public.circle_members;
create policy "Owners can remove circle members"
  on public.circle_members for delete
  to authenticated
  using (
    user_id <> (select auth.uid())
    and exists (
      select 1
      from public.circles c
      where c.id = circle_id
        and c.owner_id = (select auth.uid())
    )
  );

-- If the last accepted membership disappears, sharing is disabled
-- immediately even when the removed member's app is not open.
create or replace function private.disable_sharing_without_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if not exists (
    select 1
    from public.circle_members cm
    where cm.user_id = OLD.user_id
      and cm.is_accepted = true
  ) then
    update public.location_sharing_settings
    set
      is_sharing_enabled = false,
      is_paused = false,
      updated_at = timezone('utc', now())
    where user_id = OLD.user_id;
  end if;
  return OLD;
end;
$function$;

revoke all on function private.disable_sharing_without_membership()
  from public, anon, authenticated;

drop trigger if exists trg_disable_sharing_without_membership
  on public.circle_members;
create trigger trg_disable_sharing_without_membership
  after delete on public.circle_members
  for each row
  execute function private.disable_sharing_without_membership();

comment on function private.disable_sharing_without_membership()
  is 'Privacy guard that disables sharing after a user loses their final accepted family membership.';
