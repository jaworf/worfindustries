-- The setup screen may read its own church name even before the required
-- password change, without granting access to any church records.
create function private.account_church_branding() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('name',c.name,'slug',c.slug)
 from public.profiles p join public.churches c on c.id=p.church_id
 where p.user_id=auth.uid() and not p.access_disabled and c.is_active;
$$;
revoke all on function private.account_church_branding() from public,anon;
grant execute on function private.account_church_branding() to authenticated;
create function public.account_church_branding() returns jsonb
language sql stable security invoker set search_path='' as $$select private.account_church_branding()$$;
revoke all on function public.account_church_branding() from public,anon;
grant execute on function public.account_church_branding() to authenticated;
