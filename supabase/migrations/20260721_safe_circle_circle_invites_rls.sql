-- SafeCircle GPS: circle membership, invite, and privacy-focused RLS updates

create extension if not exists "pgcrypto";

create or replace function public.sanitized_invite_code(p_code text)
returns text
language sql immutable as $$
  select upper(trim(p_code));
$$;

create table if not exists public.circle_invites (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  code text not null,
  created_by uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  expires_at timestamptz,
  unique (code)
);

create index if not exists idx_circle_invites_circle on public.circle_invites(circle_id);
create index if not exists idx_circle_invites_code on public.circle_invites(code);

alter table public.circles
  add column if not exists invite_code text;

alter table public.circle_members
  add column if not exists is_accepted boolean not null default false;

-- Keep one membership per user per circle.
alter table public.circle_members
  drop constraint if exists circle_members_user_id_circle_id_key;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'circle_members_user_id_circle_id_key'
      and conrelid = 'public.circle_members'::regclass
  ) then
    alter table public.circle_members
      add constraint circle_members_user_id_circle_id_key unique (circle_id, user_id);
  end if;
end
$$;

-- Backfill missing invite codes and enforce uniqueness.
update public.circles
set invite_code = upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8))
where invite_code is null;

alter table public.circles
  alter column invite_code set not null;

create unique index if not exists circles_invite_code_uidx on public.circles(invite_code);

create or replace function public.random_invite_code()
returns text
language sql as $$
  select upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
$$;

create or replace function public.ensure_circle_invite_code()
returns trigger
language plpgsql as $$
begin
  if NEW.invite_code is null then
    loop
      NEW.invite_code := public.random_invite_code();
      if not exists (
        select 1 from public.circles where invite_code = NEW.invite_code
      ) then
        exit;
      end if;
    end loop;
  else
    NEW.invite_code := upper(NEW.invite_code);
  end if;
  return NEW;
end
$$;

create or replace function public.rotate_circle_invite_code(p_circle_id uuid)
returns text
language plpgsql security definer as $$
declare
  v_code text;
  v_circle_owner uuid;
begin
  select owner_id into v_circle_owner from public.circles where id = p_circle_id;
  if v_circle_owner is null then
    raise exception 'Circle not found';
  end if;

  if v_circle_owner <> auth.uid() then
    raise exception 'Only owner can rotate invite code';
  end if;

  loop
    v_code := public.random_invite_code();
    if not exists (select 1 from public.circles where invite_code = v_code) then
      update public.circles
      set invite_code = v_code
      where id = p_circle_id;

      insert into public.circle_invites(code, circle_id, created_by)
      values (v_code, p_circle_id, auth.uid())
      on conflict (code) do nothing;

      return v_code;
    end if;
  end loop;
end
$$;

create or replace function public.join_circle_by_invite_code(p_invite_code text)
returns void
language plpgsql security definer as $$
declare
  v_normalized_code text := public.sanitized_invite_code(p_invite_code);
  v_circle_id uuid;
begin
  select circle_id into v_circle_id
  from public.circle_invites
  where code = v_normalized_code
    and (expires_at is null or expires_at > timezone('utc', now()));

  if v_circle_id is null then
    select id into v_circle_id
    from public.circles
    where invite_code = v_normalized_code
    limit 1;
  end if;

  if v_circle_id is null then
    raise exception 'Invalid invite code';
  end if;

  insert into public.circle_members(circle_id, user_id, role, is_accepted, invited_at)
  values (v_circle_id, auth.uid(), 'member', true, timezone('utc', now()))
  on conflict (circle_id, user_id)
  do update
    set is_accepted = excluded.is_accepted,
        invited_at = excluded.invited_at;

  delete from public.circle_invites where code = v_normalized_code;
end
$$;

create or replace function public.sync_owner_membership()
returns trigger
language plpgsql as $$
begin
  insert into public.circle_members(circle_id, user_id, role, is_accepted, invited_at)
  values (NEW.id, NEW.owner_id, 'owner', true, timezone('utc', now()))
  on conflict (circle_id, user_id)
  do update set is_accepted = true, role = 'owner';
  return NEW;
end
$$;

-- RLS
alter table public.users enable row level security;
alter table public.circles enable row level security;
alter table public.circle_members enable row level security;
alter table public.location_updates enable row level security;
alter table public.location_sharing_settings enable row level security;
alter table public.circle_invites enable row level security;

drop policy if exists "Users can read own profile" on public.users;
drop policy if exists "Users can read peer profiles" on public.users;
drop policy if exists "Users can insert own profile" on public.users;
drop policy if exists "Users can update own profile" on public.users;

drop policy if exists "Users can create circles" on public.circles;
drop policy if exists "Users can read circles they belong to" on public.circles;
drop policy if exists "Users can read own circles" on public.circles;
drop policy if exists "Owners can update own circles" on public.circles;

drop policy if exists "Users can read members of accepted circles" on public.circle_members;
drop policy if exists "Users can view members of accepted circles" on public.circle_members;
drop policy if exists "Users can add memberships" on public.circle_members;
drop policy if exists "Users can add their own membership" on public.circle_members;
drop policy if exists "Users can update own membership" on public.circle_members;


drop policy if exists "Users can add location updates" on public.location_updates;
drop policy if exists "Users can add location updates for themselves" on public.location_updates;
drop policy if exists "Members can read shared location updates" on public.location_updates;

drop policy if exists "Users can read own sharing settings" on public.location_sharing_settings;
drop policy if exists "Users can upsert own sharing settings" on public.location_sharing_settings;
drop policy if exists "Users can modify their own sharing settings" on public.location_sharing_settings;

drop policy if exists "Admins can manage circle invites" on public.circle_invites;
drop policy if exists "Users can read invites for circles they own" on public.circle_invites;

do $$
begin
  create policy "Users can read own profile"
    on public.users for select
    using (auth.uid() = id);

  create policy "Users can read peer profiles"
    on public.users for select
    using (
      exists (
        select 1
        from public.circle_members viewer
        join public.circle_members target on viewer.circle_id = target.circle_id
        where viewer.user_id = auth.uid()
          and viewer.is_accepted = true
          and target.user_id = id
          and target.is_accepted = true
      )
    );

  create policy "Users can insert own profile"
    on public.users for insert
    with check (auth.uid() = id);

  create policy "Users can update own profile"
    on public.users for update
    using (auth.uid() = id)
    with check (auth.uid() = id);

  create policy "Users can create circles"
    on public.circles for insert
    with check (auth.uid() = owner_id);

  create policy "Users can read own circles"
    on public.circles for select
    using (
      exists (
        select 1
        from public.circle_members m
        where m.circle_id = id
          and m.user_id = auth.uid()
          and m.is_accepted = true
      )
    );

  create policy "Owners can update own circles"
    on public.circles for update
    using (auth.uid() = owner_id)
    with check (auth.uid() = owner_id);

  create policy "Users can view members of accepted circles"
    on public.circle_members for select
    using (
      exists (
        select 1
        from public.circle_members viewer
        where viewer.circle_id = circle_id
          and viewer.user_id = auth.uid()
          and viewer.is_accepted = true
      )
    );

  create policy "Users can add memberships"
    on public.circle_members for insert
    with check (auth.uid() = user_id);

  create policy "Users can update own membership"
    on public.circle_members for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

  create policy "Users can add location updates for themselves"
    on public.location_updates for insert
    with check (auth.uid() = user_id);

  create policy "Members can read shared location updates"
    on public.location_updates for select
    using (
      user_id = auth.uid()
      or exists (
        select 1
        from public.circle_members viewer
        join public.circle_members target
          on viewer.circle_id = target.circle_id
        where viewer.user_id = auth.uid()
          and viewer.is_accepted = true
          and target.user_id = user_id
          and target.is_accepted = true
      )
    );

  create policy "Users can read own sharing settings"
    on public.location_sharing_settings for select
    using (auth.uid() = user_id);

  create policy "Users can upsert own sharing settings"
    on public.location_sharing_settings for insert
    with check (auth.uid() = user_id);

  create policy "Users can modify their own sharing settings"
    on public.location_sharing_settings for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

  create policy "Users can read invites for circles they own"
    on public.circle_invites for select
    using (
      exists (
        select 1
        from public.circles c
        where c.id = circle_id
          and c.owner_id = auth.uid()
      )
    );

  create policy "Owners can manage circle invites"
    on public.circle_invites for all
    using (
      exists (
        select 1
        from public.circles c
        where c.id = circle_id
          and c.owner_id = auth.uid()
      )
    )
    with check (
      exists (
        select 1
        from public.circles c
        where c.id = circle_id
          and c.owner_id = auth.uid()
      )
    );
end
$$;

drop trigger if exists circle_invite_code_trigger on public.circles;
drop trigger if exists circle_invites_sync on public.circles;
create trigger circle_invite_code_trigger
  before insert on public.circles
  for each row
  execute function public.ensure_circle_invite_code();

drop trigger if exists circle_owner_membership_trigger on public.circles;
create trigger circle_owner_membership_trigger
  after insert on public.circles
  for each row
  execute function public.sync_owner_membership();

-- Keep invite table aligned with circles.
insert into public.circle_invites(code, circle_id, created_by)
select
  c.invite_code,
  c.id,
  c.owner_id
from public.circles c
where c.invite_code is not null
  and not exists (
    select 1
    from public.circle_invites ci
    where ci.circle_id = c.id
      and ci.code = c.invite_code
  );

-- Keep owner memberships aligned for existing rows.
insert into public.circle_members(circle_id, user_id, role, is_accepted, invited_at)
select
  c.id,
  c.owner_id,
  'owner',
  true,
  timezone('utc', now())
from public.circles c
where not exists (
  select 1
  from public.circle_members m
  where m.circle_id = c.id and m.user_id = c.owner_id
);

grant execute on function public.join_circle_by_invite_code(text) to authenticated;
grant execute on function public.rotate_circle_invite_code(uuid) to authenticated;
