-- Enforce location write privacy and ensure map realtime works.

create or replace function public.has_accepted_circle_membership(_user_id uuid)
returns boolean
language sql stable as $$
  select exists (
    select 1
    from public.circle_members
    where user_id = _user_id
      and is_accepted = true
  );
$$;

alter table public.location_updates enable row level security;

drop policy if exists "Users can add location updates for themselves" on public.location_updates;
drop policy if exists "Members can read shared location updates" on public.location_updates;

create policy "Users can add location updates for accepted members" 
  on public.location_updates for insert
  with check (
    auth.uid() = user_id
    and public.has_accepted_circle_membership(auth.uid())
  );

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

alter table public.circle_members enable row level security;

drop policy if exists "Users can view members of accepted circles" on public.circle_members;
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

alter table public.circles enable row level security;

drop policy if exists "Users can read own circles" on public.circles;
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

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'location_updates'
  ) then
    alter publication supabase_realtime add table public.location_updates;
  end if;
end
$$;
