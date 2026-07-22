-- Service-only functions must not be callable through authenticated RPC.
revoke execute on function public.delete_expired_location_updates() from authenticated;
revoke execute on function public.handle_new_user() from authenticated;
revoke execute on function public.delete_expired_location_updates() from anon, public;
revoke execute on function public.handle_new_user() from anon, public;

