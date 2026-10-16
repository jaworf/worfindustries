-- Account deletion must not be blocked by access-change audit references.
-- Keep the church's role-change history without retaining deleted account IDs.
alter table public.app_access_audit
  alter column actor_id drop not null,
  alter column user_id drop not null,
  drop constraint app_access_audit_actor_id_fkey,
  drop constraint app_access_audit_user_id_fkey;
alter table public.app_access_audit
  add constraint app_access_audit_actor_id_fkey foreign key (actor_id)
    references auth.users(id) on delete set null,
  add constraint app_access_audit_user_id_fkey foreign key (user_id)
    references auth.users(id) on delete set null;
