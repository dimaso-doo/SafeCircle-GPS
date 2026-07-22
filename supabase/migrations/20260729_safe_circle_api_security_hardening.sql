-- Final API grants and security hardening for hosted Supabase projects.

alter function public.delete_expired_location_updates() set search_path = '';
alter function public.enforce_circle_creation_limit() set search_path = '';
alter function public.enforce_circle_membership_limit() set search_path = '';
alter function public.enforce_location_sharing_settings_limit() set search_path = '';
alter function public.ensure_circle_invite_code() set search_path = '';
alter function public.get_subscription_plan(uuid) set search_path = '';
alter function public.handle_new_user() set search_path = '';
alter function public.has_accepted_circle_membership(uuid) set search_path = '';
alter function public.join_circle_by_invite_code(text) set search_path = '';
alter function public.notification_preference_enabled(uuid, text) set search_path = '';
alter function public.notify_safe_zone_event() set search_path = '';
alter function public.random_invite_code() set search_path = '';
alter function public.rotate_circle_invite_code(uuid) set search_path = '';
alter function public.safe_zone_event_access(uuid, uuid) set search_path = '';
alter function public.safe_zone_event_owner(uuid) set search_path = '';
alter function public.sanitized_invite_code(text) set search_path = '';
alter function public.sync_owner_membership() set search_path = '';
alter function public.target_in_user_circle(uuid, uuid) set search_path = '';
alter function public.touch_notification_metadata_updated_at() set search_path = '';
alter function public.touch_notification_token_seen_at() set search_path = '';
alter function public.touch_timestamp_updated_at() set search_path = '';
alter function public.user_allows_feature(uuid, text) set search_path = '';
alter function public.user_in_same_circle(uuid, uuid) set search_path = '';
alter function public.user_subscription_limits(uuid) set search_path = '';

revoke execute on all functions in schema public from public, anon;
grant execute on function public.join_circle_by_invite_code(text) to authenticated;
grant execute on function public.rotate_circle_invite_code(uuid) to authenticated;
grant execute on function public.get_subscription_plan(uuid) to authenticated;
grant execute on function public.user_subscription_limits(uuid) to authenticated;
grant execute on function public.user_allows_feature(uuid, text) to authenticated;
grant execute on function public.notification_preference_enabled(uuid, text) to authenticated;
grant execute on function public.has_accepted_circle_membership(uuid) to authenticated;
grant execute on function public.target_in_user_circle(uuid, uuid) to authenticated;
grant execute on function public.safe_zone_event_access(uuid, uuid) to authenticated;
grant execute on function public.safe_zone_event_owner(uuid) to authenticated;
grant execute on function public.user_in_same_circle(uuid, uuid) to authenticated;
grant execute on function public.delete_expired_location_updates() to service_role;
grant execute on function public.handle_new_user() to supabase_auth_admin;

drop policy if exists "Users can add own location updates" on public.location_updates;
drop policy if exists "Users can change own sharing settings" on public.location_sharing_settings;
drop policy if exists "Users can read invites for circles they own" on public.circle_invites;

drop policy if exists "Users can read own profile" on public.users;
drop policy if exists "Users can read peer profiles" on public.users;
create policy "Users can read circle profiles"
  on public.users for select
  to authenticated
  using (
    id = (select auth.uid())
    or private.shares_accepted_circle(public.users.id)
  );

alter policy "Users can insert own profile" on public.users to authenticated;
alter policy "Users can update own profile" on public.users to authenticated;
alter policy "Users can create circles" on public.circles to authenticated;
alter policy "Users can read own circles" on public.circles to authenticated;
alter policy "Owners can update own circles" on public.circles to authenticated;
alter policy "Users can add memberships" on public.circle_members to authenticated;
alter policy "Users can view members of accepted circles" on public.circle_members to authenticated;
alter policy "Users can update own membership" on public.circle_members to authenticated;
alter policy "Owners can manage circle invites" on public.circle_invites to authenticated;
alter policy "Users can add location updates for accepted members" on public.location_updates to authenticated;
alter policy "Members can read shared location updates" on public.location_updates to authenticated;
alter policy "Users can read own sharing settings" on public.location_sharing_settings to authenticated;
alter policy "Users can modify their own sharing settings" on public.location_sharing_settings to authenticated;
alter policy "Members can read safe zones" on public.safe_zones to authenticated;
alter policy "Members can create safe zones" on public.safe_zones to authenticated;
alter policy "Members can update own safe zones" on public.safe_zones to authenticated;
alter policy "Members can delete own safe zones" on public.safe_zones to authenticated;
alter policy "Members can read safe zone events" on public.safe_zone_events to authenticated;
alter policy "Users can insert safe zone events" on public.safe_zone_events to authenticated;
alter policy "Users can read own notification settings" on public.notification_settings to authenticated;
alter policy "Users can insert own notification settings" on public.notification_settings to authenticated;
alter policy "Users can update own notification settings" on public.notification_settings to authenticated;
alter policy "Users can read own notification tokens" on public.notification_tokens to authenticated;
alter policy "Users can insert own notification tokens" on public.notification_tokens to authenticated;
alter policy "Users can update own notification tokens" on public.notification_tokens to authenticated;
alter policy "Users can delete own notification tokens" on public.notification_tokens to authenticated;
alter policy "Users can read sos events in circles" on public.sos_events to authenticated;
alter policy "Users can insert own sos events" on public.sos_events to authenticated;
alter policy "Users can read own subscription" on public.user_subscriptions to authenticated;
alter policy "Subscription plans are public" on public.subscription_plans to anon, authenticated;

alter table public.circle_members
  drop constraint if exists circle_members_user_id_circle_id_key;

revoke all on all tables in schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.subscription_plans to anon;
grant select, insert, update, delete on all tables in schema public to authenticated;

