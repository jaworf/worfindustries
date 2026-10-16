-- Run against a disposable migrated local Supabase DB, or a transaction that
-- rolls back. All fixture UUIDs are isolated; no production users are changed.
begin;
insert into public.churches(id,name,slug) values
('10000000-0000-4000-8000-000000000001','Security Test A','security-test-a'),
('10000000-0000-4000-8000-000000000002','Security Test B','security-test-b');
insert into auth.users(id,email,encrypted_password,raw_user_meta_data) values
('20000000-0000-4000-8000-000000000001','security-admin-a@example.invalid','initial','{}'),
('20000000-0000-4000-8000-000000000002','security-viewer-a@example.invalid','initial','{}'),
('20000000-0000-4000-8000-000000000003','security-admin-b@example.invalid','initial','{}'),
('20000000-0000-4000-8000-000000000004','security-platform@example.invalid','initial','{}');
insert into public.profiles(user_id,app_role,church_id,is_platform_admin) values
('20000000-0000-4000-8000-000000000001','admin','10000000-0000-4000-8000-000000000001',false),
('20000000-0000-4000-8000-000000000002','viewer','10000000-0000-4000-8000-000000000001',false),
('20000000-0000-4000-8000-000000000003','admin','10000000-0000-4000-8000-000000000002',false),
('20000000-0000-4000-8000-000000000004','admin','10000000-0000-4000-8000-000000000001',true)
on conflict(user_id) do update set app_role=excluded.app_role,church_id=excluded.church_id,is_platform_admin=excluded.is_platform_admin;
insert into public.people(church_id,first_name,last_name) values
('10000000-0000-4000-8000-000000000001','Security','A'),
('10000000-0000-4000-8000-000000000002','Security','B');

-- Service-only management guards and successful transitions.
do $$
declare rejected boolean;
begin
  rejected:=false;
  begin perform public.manage_app_user_access('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000003',null,true);
  exception when others then rejected:=SQLERRM='This user belongs to another church.'; end;
  if not rejected then raise exception 'Cross-church management was not rejected'; end if;
  rejected:=false;
  begin perform public.manage_app_user_access('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',null,true);
  exception when others then rejected:=SQLERRM like 'Your own account%'; end;
  if not rejected then raise exception 'Self-removal was not rejected'; end if;
  rejected:=false;
  begin perform public.manage_app_user_access('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','admin',null);
  exception when others then rejected:=SQLERRM like 'Only a platform%'; end;
  if not rejected then raise exception 'Ordinary admin promotion was not rejected'; end if;
  rejected:=false;
  begin perform public.manage_app_user_access('20000000-0000-4000-8000-000000000004','20000000-0000-4000-8000-000000000003',null,true);
  exception when others then rejected:=SQLERRM like 'The last active%'; end;
  if not rejected then raise exception 'Last administrator removal was not rejected'; end if;
  perform public.manage_app_user_access('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','editor',null);
  perform public.manage_app_user_access('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002',null,true);
  if not (select access_disabled from public.profiles where user_id='20000000-0000-4000-8000-000000000002') then raise exception 'Access removal failed'; end if;
  perform public.manage_app_user_access('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002',null,false);
  if (select count(*) from public.app_access_audit where church_id='10000000-0000-4000-8000-000000000001')<>3 then raise exception 'Access changes were not audited'; end if;
end $$;

-- Test the actual authenticated role, not privileged queries alone.
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$
begin
 if (select count(*) from public.people where first_name='Security')<>1 then raise exception 'Tenant read isolation failed'; end if;
 if exists(select 1 from public.people where church_id='10000000-0000-4000-8000-000000000002') then raise exception 'Cross-church read allowed'; end if;
 if has_table_privilege('authenticated','public.profiles','UPDATE') then raise exception 'Profile mutation bypass enabled'; end if;
 if has_function_privilege('authenticated','public.manage_app_user_access(uuid,uuid,text,boolean)','EXECUTE') then raise exception 'Management RPC bypass enabled'; end if;
 begin
   insert into public.people(church_id,first_name,last_name) values('10000000-0000-4000-8000-000000000002','Forbidden','Write');
   raise exception 'Cross-church write allowed';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.profiles set access_disabled=true where user_id='20000000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ begin if exists(select 1 from public.people where first_name='Security') then raise exception 'Removed user retained data access'; end if; end $$;
reset role;
update public.profiles set access_disabled=false,must_change_password=true where user_id='20000000-0000-4000-8000-000000000002';
set local role authenticated;
do $$ begin if exists(select 1 from public.people where first_name='Security') then raise exception 'Temporary-password user accessed data'; end if; end $$;
reset role;
update auth.users set encrypted_password='changed' where id='20000000-0000-4000-8000-000000000002';
do $$ begin if (select must_change_password from public.profiles where user_id='20000000-0000-4000-8000-000000000002') then raise exception 'Password change did not clear restriction'; end if; end $$;
set local role authenticated;
do $$ begin if (select count(*) from public.people where first_name='Security')<>1 then raise exception 'Password change did not restore scoped access'; end if; end $$;
reset role;

-- Team membership is independent of elected positions, even in a voted ministry.
do $$
declare church uuid := '10000000-0000-4000-8000-000000000001';
  person uuid; ministry uuid; position uuid; placement uuid;
begin
  select id into person from public.people where church_id=church and first_name='Security' limit 1;
  insert into public.roles(church_id,name,requires_vote) values(church,'Team requirement test',true) returning id into ministry;
  insert into public.assignments(church_id,person_id,role_id) values(church,person,ministry) returning id into placement;
  if exists(select 1 from public.assignment_details where id=placement and (requires_vote or vote_missing or term_id is not null)) then
    raise exception 'A team member incorrectly requires a term or vote';
  end if;
  insert into public.sub_roles(church_id,role_id,name,requires_vote) values(church,ministry,'Elected head',true) returning id into position;
  update public.assignments set sub_role_id=position where id=placement;
  if not exists(select 1 from public.assignment_details where id=placement and requires_vote and vote_missing) then
    raise exception 'An elected position lost its vote requirement';
  end if;
  update public.assignments set sub_role_id=null where id=placement;
  if exists(select 1 from public.assignment_details where id=placement and (requires_vote or vote_missing)) then
    raise exception 'Clearing a position did not remove its vote requirement';
  end if;
end $$;

-- Deletion removes the sign-in profile and anonymizes account references in
-- role-change history, without removing church-owned volunteer records.
delete from auth.users where id='20000000-0000-4000-8000-000000000002';
do $$ begin
  if exists(select 1 from public.profiles where user_id='20000000-0000-4000-8000-000000000002') then
    raise exception 'Deleted account retained its profile';
  end if;
  if exists(select 1 from public.app_access_audit where actor_id='20000000-0000-4000-8000-000000000002' or user_id='20000000-0000-4000-8000-000000000002') then
    raise exception 'Audit history retained a deleted account ID';
  end if;
  if not exists(select 1 from public.people where church_id='10000000-0000-4000-8000-000000000001' and first_name='Security') then
    raise exception 'Account deletion removed church-owned volunteer records';
  end if;
end $$;
rollback;
