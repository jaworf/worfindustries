alter table public.profiles add column access_disabled boolean not null default false;
alter table public.profiles add column must_change_password boolean not null default false;

create or replace function private.current_church_id() returns uuid language sql stable security definer set search_path = '' as $$
 select church_id from public.profiles where user_id = (select auth.uid()) and not access_disabled and not must_change_password;
$$;
create or replace function private.has_church_role(p_church_id uuid, allowed_roles text[]) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where user_id = (select auth.uid()) and church_id = p_church_id and app_role = any(allowed_roles) and not access_disabled and not must_change_password);
$$;
create or replace function private.has_ministry_role(allowed_roles text[]) returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where user_id = (select auth.uid()) and church_id is not null and app_role = any(allowed_roles) and not access_disabled and not must_change_password);
$$;
create or replace function private.is_platform_admin() returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.profiles where user_id = (select auth.uid()) and is_platform_admin and not access_disabled and not must_change_password);
$$;
-- Access flags and roles can only be changed through the checked administrator endpoint.
revoke update on public.profiles from authenticated;

create table public.app_access_audit (
 id bigint generated always as identity primary key,
 church_id uuid not null references public.churches(id),
 actor_id uuid not null references auth.users(id),
 user_id uuid not null references auth.users(id),
 before_access jsonb not null,
 after_access jsonb not null,
 created_at timestamptz not null default now()
);
alter table public.app_access_audit enable row level security;
create policy app_access_audit_admin_read on public.app_access_audit for select to authenticated using(private.has_church_role(church_id,array['admin']));
grant select on public.app_access_audit to authenticated;
grant all on public.app_access_audit to service_role;
grant usage, select on sequence public.app_access_audit_id_seq to service_role;

create or replace function public.manage_app_user_access(p_actor_id uuid,p_user_id uuid,p_role text default null,p_disabled boolean default null) returns void language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; target public.profiles; new_role text; new_disabled boolean;
begin
 select * into target from public.profiles where user_id=p_user_id;
 if not found then raise exception 'App user not found.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(target.church_id::text,0));
 select * into actor from public.profiles where user_id=p_actor_id;
 select * into target from public.profiles where user_id=p_user_id for update;
 if actor.app_role is distinct from 'admin' or actor.access_disabled or actor.must_change_password then raise exception 'Administrator access required.'; end if;
 if not actor.is_platform_admin and actor.church_id is distinct from target.church_id then raise exception 'This user belongs to another church.'; end if;
 if target.user_id=p_actor_id or target.is_platform_admin then raise exception 'Your own account and platform administrator accounts are protected.'; end if;
 new_role:=coalesce(p_role,target.app_role); new_disabled:=coalesce(p_disabled,target.access_disabled);
 if new_role not in ('admin','editor','viewer') then raise exception 'Invalid access role.'; end if;
 if not actor.is_platform_admin and (target.app_role='admin' or new_role='admin') then raise exception 'Only a platform administrator can manage administrator access.'; end if;
 if target.app_role='admin' and not target.access_disabled and (new_role<>'admin' or new_disabled) and (select count(*) from public.profiles where church_id=target.church_id and app_role='admin' and not access_disabled and not must_change_password)<=1 then raise exception 'The last active church administrator cannot be removed.'; end if;
 update public.profiles set app_role=new_role,access_disabled=new_disabled where user_id=p_user_id;
 insert into public.app_access_audit(church_id,actor_id,user_id,before_access,after_access) values(target.church_id,p_actor_id,p_user_id,jsonb_build_object('role',target.app_role,'disabled',target.access_disabled),jsonb_build_object('role',new_role,'disabled',new_disabled));
end;
$$;
revoke all on function public.manage_app_user_access(uuid,uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.manage_app_user_access(uuid,uuid,text,boolean) to service_role;

create or replace function private.complete_initial_password_change() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if new.encrypted_password is distinct from old.encrypted_password then
  update public.profiles set must_change_password=false where user_id=new.id and must_change_password;
 end if;
 return new;
end;
$$;
revoke all on function private.complete_initial_password_change() from public,anon,authenticated;
create trigger complete_initial_password_change after update of encrypted_password on auth.users for each row execute function private.complete_initial_password_change();
