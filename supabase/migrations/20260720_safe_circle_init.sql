-- SafeCircle GPS schema
create extension if not exists "pgcrypto";
create extension if not exists "uuid-ossp";

-- users: mirrors auth users with minimal profile fields
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

create table if not exists public.circles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.circle_members (
  id uuid primary key default gen_random_uuid(),
  circle_id uuid not null references public.circles(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  role text not null default 'member',
  invited_at timestamptz not null default timezone('utc', now()),
  unique (circle_id, user_id)
);

create table if not exists public.location_updates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  latitude numeric(10,7) not null,
  longitude numeric(10,7) not null,
  altitude numeric,
  accuracy_meters numeric,
  speed_mps numeric,
  heading_degrees numeric,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.location_sharing_settings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  is_sharing_enabled boolean not null default true,
  is_paused boolean not null default false,
  updated_at timestamptz not null default timezone('utc', now()),
  unique (user_id)
);

create or replace function public.user_in_same_circle(_viewer uuid, _target uuid)
returns boolean
language sql stable as $$
  select exists (
    select 1
    from public.circle_members viewer
    join public.circle_members target on viewer.circle_id = target.circle_id
    where viewer.user_id = _viewer and target.user_id = _target
  );
$$;

alter table public.users enable row level security;
alter table public.circles enable row level security;
alter table public.circle_members enable row level security;
alter table public.location_updates enable row level security;
alter table public.location_sharing_settings enable row level security;

create policy "Users can read own profile"
  on public.users for select
  using (auth.uid() = id);

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

create policy "Users can read circles they belong to"
  on public.circles for select
  using (
    public.user_in_same_circle(auth.uid(), owner_id)
    or exists (select 1 from public.circle_members cm where cm.circle_id = id and cm.user_id = auth.uid())
  );

create policy "Owners can update own circles"
  on public.circles for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "Users manage own memberships"
  on public.circle_members for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can read memberships in their circles"
  on public.circle_members for select
  using (
    exists (
      select 1 from public.circle_members m
      where m.circle_id = circle_id and m.user_id = auth.uid()
    )
  );

create policy "Users can add own location updates"
  on public.location_updates for insert
  with check (auth.uid() = user_id);

create policy "Members can read shared location updates"
  on public.location_updates for select
  using (
    user_id = auth.uid()
    or public.user_in_same_circle(auth.uid(), user_id)
  );

create policy "Users can read own sharing settings"
  on public.location_sharing_settings for select
  using (auth.uid() = user_id);

create policy "Users can update own sharing settings"
  on public.location_sharing_settings for insert
  with check (auth.uid() = user_id);

create policy "Users can change own sharing settings"
  on public.location_sharing_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists idx_circle_members_user on public.circle_members(user_id);
create index if not exists idx_circle_members_circle on public.circle_members(circle_id);
create index if not exists idx_location_updates_user_created on public.location_updates(user_id, created_at desc);
create index if not exists idx_location_updates_created on public.location_updates(created_at desc);
