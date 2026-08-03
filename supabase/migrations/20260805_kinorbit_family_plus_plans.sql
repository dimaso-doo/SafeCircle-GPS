-- KinOrbit business model:
-- Free: 1 family, 3 members total, 24-hour history.
-- Family+: 3 families, 10 members per family, 30-day history.
-- Live location quality is the same for every plan.
-- Legacy safe-zone data is retained, but the feature is disabled.

update public.subscription_plans
set
  name = 'Free',
  max_circles = 1,
  max_members_per_circle = 3,
  max_history_retention_hours = 24,
  allow_safe_zones = false,
  allow_sos = false,
  allow_priority_updates = true,
  updated_at = now()
where slug = 'free';

update public.subscription_plans
set
  name = 'Family+',
  max_circles = 3,
  max_members_per_circle = 10,
  max_history_retention_hours = 720,
  allow_safe_zones = false,
  allow_sos = false,
  allow_priority_updates = true,
  updated_at = now()
where slug = 'premium';

create or replace function public.enforce_circle_membership_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_owner_limits record;
  v_member_limits record;
  v_circle_member_count integer;
  v_user_family_count integer;
begin
  if new.membership_status <> 'accepted' then
    return new;
  end if;

  select c.owner_id
  into v_owner_id
  from public.circles c
  where c.id = new.circle_id;

  if v_owner_id is null then
    raise exception 'Family does not exist.';
  end if;

  select *
  into v_owner_limits
  from public.user_subscription_limits(v_owner_id);

  select count(*)
  into v_circle_member_count
  from public.circle_members cm
  where cm.circle_id = new.circle_id
    and cm.membership_status = 'accepted'
    and (tg_op <> 'UPDATE' or cm.id <> new.id);

  if v_circle_member_count >= v_owner_limits.max_members_per_circle then
    raise exception
      'This family allows up to % members. Upgrade the owner to Family+ for more.',
      v_owner_limits.max_members_per_circle;
  end if;

  select *
  into v_member_limits
  from public.user_subscription_limits(new.user_id);

  select count(*)
  into v_user_family_count
  from public.circle_members cm
  where cm.user_id = new.user_id
    and cm.membership_status = 'accepted'
    and (tg_op <> 'UPDATE' or cm.id <> new.id);

  if v_user_family_count >= v_member_limits.max_circles then
    raise exception
      'Your plan allows up to % families. Upgrade to Family+ for more.',
      v_member_limits.max_circles;
  end if;

  return new;
end;
$$;

comment on function public.enforce_circle_membership_limit() is
  'Applies the family owner member cap and each joining user family cap.';
