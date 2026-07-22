-- Defense in depth: the API accepts a location only while the user has
-- explicitly enabled sharing and has not paused it.
drop policy if exists "Users can insert own sharing settings" on public.location_sharing_settings;
create policy "Users can insert own sharing settings"
  on public.location_sharing_settings for insert
  to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "Users can add location updates for accepted members" on public.location_updates;
create policy "Users can add active shared locations"
  on public.location_updates for insert
  to authenticated
  with check (
    user_id = (select auth.uid())
    and public.has_accepted_circle_membership((select auth.uid()))
    and exists (
      select 1
      from public.location_sharing_settings settings
      where settings.user_id = (select auth.uid())
        and settings.is_sharing_enabled = true
        and settings.is_paused = false
    )
  );

