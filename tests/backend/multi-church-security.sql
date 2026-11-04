
begin;
do $$begin
 if not has_table_privilege('service_role','public.churches','SELECT,INSERT,UPDATE,DELETE') then raise exception 'Fresh-project service grants are incomplete';end if;
end $$;
insert into public.churches(id,name,slug) values
 ('10000000-0000-4000-8000-000000000001','Church A','test-a'),('10000000-0000-4000-8000-000000000002','Church B','test-b');
insert into auth.users(id,email,email_confirmed_at) values
 ('20000000-0000-4000-8000-000000000001','admin-a@example.invalid',now()),
 ('20000000-0000-4000-8000-000000000002','viewer-a@example.invalid',now()),
 ('20000000-0000-4000-8000-000000000003','admin-b@example.invalid',now()),
 ('20000000-0000-4000-8000-000000000004','platform@example.invalid',now()),
 ('20000000-0000-4000-8000-000000000005','applicant@example.invalid',now()),
 ('20000000-0000-4000-8000-000000000006','applicant-two@example.invalid',now());
update public.profiles set church_id='10000000-0000-4000-8000-000000000001',app_role='admin' where user_id in('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000004');
update public.profiles set is_platform_admin=true where user_id='20000000-0000-4000-8000-000000000004';
update public.profiles set church_id='10000000-0000-4000-8000-000000000001' where user_id='20000000-0000-4000-8000-000000000002';
update public.profiles set church_id='10000000-0000-4000-8000-000000000002',app_role='admin' where user_id='20000000-0000-4000-8000-000000000003';
insert into public.church_applications(id,applicant_id,church_name,location) values
 ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000005','Applicant Church','Pasco, WA'),
 ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000006','Declined Church','Portland, OR');
do $$declare rejected boolean:=false; c uuid; begin
 begin perform public.decide_church_application('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',true,'');
 exception when others then rejected:=SQLERRM='Platform administrator access required.';end;
 if not rejected then raise exception 'Church admin approved a church';end if;
 if (select church_id from public.profiles where user_id='20000000-0000-4000-8000-000000000005') is not null then raise exception 'Pending applicant has membership';end if;
 c:=public.decide_church_application('20000000-0000-4000-8000-000000000004','30000000-0000-4000-8000-000000000001',true,'Welcome');
 if not exists(select 1 from public.profiles where user_id='20000000-0000-4000-8000-000000000005' and church_id=c and app_role='admin' and not is_platform_admin) then raise exception 'Approval did not assign scoped admin';end if;
 rejected:=false;
 begin perform public.decide_church_application('20000000-0000-4000-8000-000000000004','30000000-0000-4000-8000-000000000001',true,'');
 exception when others then rejected:=SQLERRM='This application has already been decided.';end;
 if not rejected then raise exception 'Duplicate approval created another church';end if;
 perform public.decide_church_application('20000000-0000-4000-8000-000000000004','30000000-0000-4000-8000-000000000002',false,'Not approved');
 if (select church_id from public.profiles where user_id='20000000-0000-4000-8000-000000000006') is not null then raise exception 'Rejected applicant received membership';end if;
 perform public.manage_app_user_access('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','admin',null);
 if not exists(select 1 from public.profiles where user_id='20000000-0000-4000-8000-000000000002' and app_role='admin') then raise exception 'Church admin cannot delegate';end if;
 perform public.manage_app_user_access('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','editor',null);
 rejected:=false;
 begin perform public.record_platform_support('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','read_diagnostics','Investigating a sign-in issue');
 exception when others then rejected:=SQLERRM='Platform administrator access required.';end;
 if not rejected then raise exception 'Church administrator obtained support access';end if;
 perform public.record_platform_support('20000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000002','read_diagnostics','Investigating a sign-in issue');
 if not exists(select 1 from public.platform_support_audit where church_id='10000000-0000-4000-8000-000000000002' and action='read_diagnostics') then raise exception 'Support access was not audited';end if;
end $$;
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000006',true);
set local role authenticated;
do $$begin
 if (select count(*) from public.church_applications)<>1 then raise exception 'Application RLS leaked other applicants';end if;
 if exists(select 1 from public.platform_support_audit) then raise exception 'Support audit leaked to applicant';end if;
 if has_function_privilege('authenticated','public.decide_church_application(uuid,uuid,boolean,text)','EXECUTE') then raise exception 'Applicant can call approval RPC';end if;
 begin insert into public.church_applications(applicant_id,church_name,location) values('20000000-0000-4000-8000-000000000006','Forged','Location');raise exception 'Direct application write allowed';exception when insufficient_privilege then null;end;
end $$;

reset role;
do $$declare rejected boolean:=false;begin
 begin delete from auth.users where id='20000000-0000-4000-8000-000000000003';
 exception when others then rejected:=SQLERRM like 'Appoint another church%';end;
 if not rejected then raise exception 'Last church administrator deletion succeeded';end if;
 rejected:=false;
 begin delete from auth.users where id='20000000-0000-4000-8000-000000000004';
 exception when others then rejected:=SQLERRM like 'Appoint another platform%';end;
 if not rejected then raise exception 'Last platform administrator deletion succeeded';end if;
 rejected:=false;
 begin perform public.manage_app_user_access('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000004',null,true);
 exception when others then rejected:=SQLERRM like 'Your own account%';end;
 if not rejected then raise exception 'Church administrator disabled platform owner';end if;
end $$;

select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000004',true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.profiles where church_id='10000000-0000-4000-8000-000000000002') then raise exception 'Platform ordinary session bypassed church scoping';end if;
 if has_function_privilege('authenticated','public.support_sync_status(uuid,uuid)','EXECUTE') then raise exception 'Direct support RPC bypass allowed';end if;
end $$;
reset role;
update public.churches set is_active=false where id='10000000-0000-4000-8000-000000000001';
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$begin if private.has_church_role('10000000-0000-4000-8000-000000000001',array['admin']) then raise exception 'Inactive workspace retained church role';end if;end $$;
reset role;

-- Pending administrators do not count as active administrators, and may be
-- demoted without locking the sole active administrator out of management.
update public.churches set is_active=true where id='10000000-0000-4000-8000-000000000001';
update public.profiles set must_change_password=true where user_id='20000000-0000-4000-8000-000000000002';
select public.manage_app_user_access('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','admin',null);
select public.manage_app_user_access('20000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','editor',null);
update public.profiles set must_change_password=false where user_id='20000000-0000-4000-8000-000000000002';

-- Logo metadata uses actual Storage RLS under authenticated church roles.
-- This rolled-back fixture has metadata rows only, never uploaded files.
-- Match the Storage API's transaction flag so its statement guard does not
-- obscure the cross-church DELETE RLS assertion (RLS remains enabled).
-- https://github.com/supabase/supabase/blob/master/apps/www/_blog/2026-03-05-supabase-storage-performance-security-reliability-updates.mdx
select set_config('storage.allow_delete_query','true',true);
update public.churches set is_active=true where id='10000000-0000-4000-8000-000000000001';
insert into storage.objects(bucket_id,name) values('church-logos','10000000-0000-4000-8000-000000000002/logo');
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000001',true);
set local role authenticated;
insert into storage.objects(bucket_id,name) values('church-logos','10000000-0000-4000-8000-000000000001/logo');
-- Replacing an existing logo requires SELECT, INSERT and UPDATE policies.
insert into storage.objects(bucket_id,name) values('church-logos','10000000-0000-4000-8000-000000000001/logo') on conflict(bucket_id,name) do update set name=excluded.name;
do $$declare changed int;begin
 if (select count(*) from storage.objects where bucket_id='church-logos')<>1 then raise exception 'Another church logo was readable';end if;
 begin insert into storage.objects(bucket_id,name) values('church-logos','10000000-0000-4000-8000-000000000002/forged');raise exception 'Cross-church logo upload allowed';exception when insufficient_privilege then null;end;
 update storage.objects set name=name where name='10000000-0000-4000-8000-000000000002/logo';get diagnostics changed=row_count;
 if changed<>0 then raise exception 'Another church logo was replaceable';end if;
 delete from storage.objects where name='10000000-0000-4000-8000-000000000002/logo';get diagnostics changed=row_count;
 if changed<>0 then raise exception 'Another church logo was deletable';end if;
 begin update storage.objects set name='10000000-0000-4000-8000-000000000002/logo' where name='10000000-0000-4000-8000-000000000001/logo';raise exception 'Logo reassignment allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.profiles set app_role='viewer' where user_id='20000000-0000-4000-8000-000000000002';
select set_config('request.jwt.claim.sub','20000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$declare changed int;begin
 if (select count(*) from storage.objects where bucket_id='church-logos')<>1 then raise exception 'Viewer cannot read own church logo';end if;
 update storage.objects set name=name where name='10000000-0000-4000-8000-000000000001/logo';get diagnostics changed=row_count;
 if changed<>0 then raise exception 'Viewer changed church logo';end if;
end $$;
reset role;
do $$begin if (select public from storage.buckets where id='church-logos') then raise exception 'Church logos were made public';end if;end $$;
-- Direct-role regression: private recruitment rows stay inside editor/admin access.
reset role;
insert into public.churches(id,name,slug) values
 ('a1000000-0000-4000-8000-000000000001','Privacy Church','privacy-regression-a'),
 ('a1000000-0000-4000-8000-000000000002','Other Privacy Church','privacy-regression-b');
insert into auth.users(id,email,email_confirmed_at) values
 ('a2000000-0000-4000-8000-000000000001','privacy-admin@example.invalid',now()),
 ('a2000000-0000-4000-8000-000000000002','privacy-editor@example.invalid',now()),
 ('a2000000-0000-4000-8000-000000000003','privacy-viewer@example.invalid',now()),
 ('a2000000-0000-4000-8000-000000000004','privacy-other-admin@example.invalid',now());
update public.profiles set church_id='a1000000-0000-4000-8000-000000000001',app_role=case when user_id='a2000000-0000-4000-8000-000000000001' then 'admin' when user_id='a2000000-0000-4000-8000-000000000002' then 'editor' else 'viewer' end
 where user_id in ('a2000000-0000-4000-8000-000000000001','a2000000-0000-4000-8000-000000000002','a2000000-0000-4000-8000-000000000003');
update public.profiles set church_id='a1000000-0000-4000-8000-000000000002',app_role='admin' where user_id='a2000000-0000-4000-8000-000000000004';
insert into public.roles(id,church_id,name) values
 ('a3000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Privacy Ministry'),
 ('a3000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002','Other Ministry');
insert into public.people(id,church_id,first_name,last_name) values
 ('a4000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','Private','Candidate'),
 ('a4000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002','Other','Candidate');
insert into public.placement_openings(id,church_id,role_id) values
 ('a5000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000001'),
 ('a5000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002','a3000000-0000-4000-8000-000000000002');
insert into public.placement_candidates(id,church_id,opening_id,person_id,response) values
 ('a6000000-0000-4000-8000-000000000001','a1000000-0000-4000-8000-000000000001','a5000000-0000-4000-8000-000000000001','a4000000-0000-4000-8000-000000000001','no'),
 ('a6000000-0000-4000-8000-000000000002','a1000000-0000-4000-8000-000000000002','a5000000-0000-4000-8000-000000000002','a4000000-0000-4000-8000-000000000002','maybe_later');
insert into public.volunteer_contact_history(church_id,candidate_id,person_id,kind,happened_on,response,notes,recorded_by,recorder_name,role_label)
 select c.church_id,c.id,c.person_id,'call',current_date,c.response,'Private response explanation',case when c.church_id='a1000000-0000-4000-8000-000000000001' then 'a2000000-0000-4000-8000-000000000001'::uuid else 'a2000000-0000-4000-8000-000000000004'::uuid end,'Test Recorder','Privacy Ministry'
 from public.placement_candidates c where c.id in ('a6000000-0000-4000-8000-000000000001','a6000000-0000-4000-8000-000000000002');
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000003',true);
set local role authenticated;
do $$begin
 if exists(select 1 from public.placement_candidates) then raise exception 'Viewer read private recruitment candidates';end if;
 if exists(select 1 from public.volunteer_contact_history) then raise exception 'Viewer read private call notes';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$begin
 if (select count(*) from public.placement_candidates)<>1 then raise exception 'Admin recruitment visibility is incorrect';end if;
 if (select count(*) from public.volunteer_contact_history)<>1 then raise exception 'Admin call history visibility is incorrect';end if;
 if exists(select 1 from public.placement_candidates where church_id='a1000000-0000-4000-8000-000000000002') then raise exception 'Admin read other church candidates';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000002',true);
set local role authenticated;
do $$begin
 if (select count(*) from public.placement_candidates)<>1 then raise exception 'Editor recruitment visibility is incorrect';end if;
 if (select count(*) from public.volunteer_contact_history)<>1 then raise exception 'Editor call history visibility is incorrect';end if;
 if exists(select 1 from public.volunteer_contact_history where church_id='a1000000-0000-4000-8000-000000000002') then raise exception 'Editor read other church call notes';end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','a2000000-0000-4000-8000-000000000004',true);
set local role authenticated;
do $$begin
 if (select count(*) from public.placement_candidates)<>1 then raise exception 'Other church admin visibility is incorrect';end if;
 if exists(select 1 from public.volunteer_contact_history where church_id='a1000000-0000-4000-8000-000000000001') then raise exception 'Other church admin read private call notes';end if;
end $$;
reset role;

rollback;
