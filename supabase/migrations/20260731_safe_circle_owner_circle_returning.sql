-- Allow the creator to read the inserted circle in PostgREST RETURNING before
-- the AFTER INSERT owner-membership trigger has completed.
alter policy "Users can read own circles"
  on public.circles
  to authenticated
  using (
    owner_id = (select auth.uid())
    or private.is_accepted_circle_member(public.circles.id)
  );

