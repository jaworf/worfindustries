-- Explicit server grants also support fresh projects with no automatic grants.
grant all on public.churches to service_role;

-- Approval is a separate privilege from church administration. No public
-- signup, user metadata, or church admin can assign platform privileges.
create table public.church_applications (
 id uuid primary key default gen_random_uuid(),
 applicant_id uuid references auth.users(id) on delete set null,
 church_name text not null check(length(btrim(church_name)) between 2 and 160),
 location text not null check(length(btrim(location)) between 2 and 240),
 status text not null default 'pending' check(status in ('pending','approved','rejected')),
 church_id uuid references public.churches(id),
 decided_by uuid references auth.users(id) on delete set null,
 decision_note text check(length(decision_note)<=1000),
 created_at timestamptz not null default now(),
 decided_at timestamptz
);
create unique index one_pending_church_application on public.church_applications(applicant_id) where status='pending';
create index church_applications_status_created on public.church_applications(status,created_at);
alter table public.church_applications enable row level security;
revoke all on public.church_applications from anon,authenticated;
grant select on public.church_applications to authenticated;
grant all on public.church_applications to service_role;
create policy church_application_read on public.church_applications for select to authenticated
 using(applicant_id=(select auth.uid()) or private.is_platform_admin());

create table public.platform_support_audit (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid references auth.users(id) on delete set null,
 church_id uuid references public.churches(id),
 action text not null,
 reason text not null check(length(btrim(reason)) between 10 and 1000),
 created_at timestamptz not null default now()
);
create index platform_support_audit_church_created on public.platform_support_audit(church_id,created_at desc);
alter table public.platform_support_audit enable row level security;
revoke all on public.platform_support_audit from anon,authenticated;
grant select on public.platform_support_audit to authenticated;
grant all on public.platform_support_audit to service_role;
create policy platform_support_audit_read on public.platform_support_audit for select to authenticated using(private.is_platform_admin());

-- RPCs are service-only: actor IDs come from verified Auth tokens in the edge
-- handler. These transactions retain an independent database authorization check.
create or replace function public.decide_church_application(p_actor_id uuid,p_application_id uuid,p_approve boolean,p_note text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare a public.church_applications; c uuid; actor public.profiles; applicant public.profiles;
begin
 select * into actor from public.profiles where user_id=p_actor_id;
 if actor.user_id is null or not actor.is_platform_admin or actor.app_role<>'admin' or actor.access_disabled or actor.must_change_password then
  raise exception 'Platform administrator access required.';
 end if;
 if p_approve is null or length(p_note)>1000 then raise exception 'Invalid decision.'; end if;
 select * into a from public.church_applications where id=p_application_id for update;
 if not found then raise exception 'Application not found.'; end if;
 if a.status<>'pending' then raise exception 'This application has already been decided.'; end if;
 if p_approve then
  select * into applicant from public.profiles where user_id=a.applicant_id for update;
  if not found or applicant.church_id is not null or applicant.is_platform_admin or applicant.access_disabled then
   raise exception 'The applicant is unavailable or already belongs to a church.';
  end if;
  if not exists(select 1 from auth.users where id=a.applicant_id and email_confirmed_at is not null) then
   raise exception 'The applicant must verify their email first.';
  end if;
  insert into public.churches(name,slug,public_directory_enabled)
   values(a.church_name,'church-'||replace(a.id::text,'-',''),false) returning id into c;
  update public.profiles set church_id=c,app_role='admin',must_change_password=false where user_id=a.applicant_id;
 end if;
 update public.church_applications set status=case when p_approve then 'approved' else 'rejected' end,
 church_id=c,decided_by=p_actor_id,decision_note=p_note,decided_at=now() where id=a.id;
 insert into public.platform_support_audit(actor_id,church_id,action,reason)
 values(p_actor_id,c,case when p_approve then 'approve_church' else 'reject_church' end,'Application decision: '||a.id::text);
 return c;
end;$$;
revoke all on function public.decide_church_application(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.decide_church_application(uuid,uuid,boolean,text) to service_role;

create or replace function public.record_platform_support(p_actor_id uuid,p_church_id uuid,p_action text,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where user_id=p_actor_id and is_platform_admin and app_role='admin' and not access_disabled and not must_change_password) then
  raise exception 'Platform administrator access required.';
 end if;
 if not exists(select 1 from public.churches where id=p_church_id) then raise exception 'Church not found.'; end if;
 insert into public.platform_support_audit(actor_id,church_id,action,reason) values(p_actor_id,p_church_id,p_action,p_reason);
end;$$;
revoke all on function public.record_platform_support(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.record_platform_support(uuid,uuid,text,text) to service_role;

-- Every church role checks activity, so deactivated workspaces fail closed.
create or replace function private.has_church_role(p_church_id uuid,allowed_roles text[])
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p join public.churches c on c.id=p.church_id
 where p.user_id=(select auth.uid()) and p.church_id=p_church_id and p.app_role=any(allowed_roles)
 and not p.access_disabled and not p.must_change_password and c.is_active);
$$;

create or replace function public.manage_app_user_access(p_actor_id uuid,p_user_id uuid,p_role text default null,p_disabled boolean default null) returns void language plpgsql security definer set search_path = '' as $$
declare actor public.profiles; target public.profiles; new_role text; new_disabled boolean;
begin
 select * into target from public.profiles where user_id=p_user_id;
 if not found then raise exception 'App user not found.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(target.church_id::text,0));
 select * into actor from public.profiles where user_id=p_actor_id;
 select * into target from public.profiles where user_id=p_user_id for update;
 if actor.user_id is null or actor.church_id is null or actor.app_role is distinct from 'admin' or actor.access_disabled or actor.must_change_password or not exists(select 1 from public.churches where id=actor.church_id and is_active) then raise exception 'Administrator access required.'; end if;
 if not actor.is_platform_admin and actor.church_id is distinct from target.church_id then raise exception 'This user belongs to another church.'; end if;
 if target.user_id=p_actor_id or target.is_platform_admin then raise exception 'Your own account and platform administrator accounts are protected.'; end if;
 new_role:=coalesce(p_role,target.app_role); new_disabled:=coalesce(p_disabled,target.access_disabled);
 if new_role not in ('admin','editor','viewer') then raise exception 'Invalid access role.'; end if;

 if target.app_role='admin' and not target.access_disabled and not target.must_change_password and (new_role<>'admin' or new_disabled) and (select count(*) from public.profiles where church_id=target.church_id and app_role='admin' and not access_disabled and not must_change_password)<=1 then raise exception 'The last active church administrator cannot be removed.'; end if;
 update public.profiles set app_role=new_role,access_disabled=new_disabled where user_id=p_user_id;
 insert into public.app_access_audit(church_id,actor_id,user_id,before_access,after_access) values(target.church_id,p_actor_id,p_user_id,jsonb_build_object('role',target.app_role,'disabled',target.access_disabled),jsonb_build_object('role',new_role,'disabled',new_disabled));
end;
$$;
revoke all on function public.manage_app_user_access(uuid,uuid,text,boolean) from public,anon,authenticated;
grant execute on function public.manage_app_user_access(uuid,uuid,text,boolean) to service_role;


create or replace function public.support_sync_status(p_actor_id uuid,p_church_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.profiles where user_id=p_actor_id and is_platform_admin and app_role='admin' and not access_disabled and not must_change_password) then raise exception 'Platform administrator access required.'; end if;
 return coalesce((select jsonb_build_object('connected',true,'last_synced_at',last_synced_at,'last_sync_status',last_sync_status) from private.planning_center_connections where church_id=p_church_id),'{"connected":false}'::jsonb);
end;$$;
revoke all on function public.support_sync_status(uuid,uuid) from public,anon,authenticated;
grant execute on function public.support_sync_status(uuid,uuid) to service_role;

-- Auth deletion and delegation share a church advisory lock. Even two concurrent
-- departures cannot delete the final active administrator of an active church.
create or replace function private.protect_last_administrator()
returns trigger language plpgsql security definer set search_path='' as $$
declare p public.profiles;
begin
 select * into p from public.profiles where user_id=old.id;
 if p.is_platform_admin then
  perform pg_advisory_xact_lock(hashtextextended('ministry-platform-administrators',0));
 end if;
 if p.church_id is not null then
  perform pg_advisory_xact_lock(hashtextextended(p.church_id::text,0));
 end if;
 if p.is_platform_admin and not exists(select 1 from public.profiles where is_platform_admin and app_role='admin' and not access_disabled and not must_change_password and user_id<>old.id) then
  raise exception 'Appoint another platform administrator before deleting this account.';
 end if;
 if p.app_role='admin' and not p.access_disabled and not p.must_change_password
 and exists(select 1 from public.churches where id=p.church_id and is_active)
 and not exists(select 1 from public.profiles where church_id=p.church_id and app_role='admin' and not access_disabled and not must_change_password and user_id<>old.id) then
  raise exception 'Appoint another church administrator before deleting this account.';
 end if;
 return old;
end;$$;
revoke all on function private.protect_last_administrator() from public,anon,authenticated;
create trigger protect_last_administrator before delete on auth.users for each row execute function private.protect_last_administrator();

-- Normal browser sessions, including the platform owner's session, see only
-- their own church. Cross-church diagnostics use the recorded support endpoint.
drop policy profiles_tenant_read on public.profiles;
create policy profiles_tenant_read on public.profiles for select to authenticated
 using(user_id=(select auth.uid()) or church_id=private.current_church_id());
drop policy churches_member_read on public.churches;
create policy churches_member_read on public.churches for select to authenticated
 using(id=private.current_church_id());
