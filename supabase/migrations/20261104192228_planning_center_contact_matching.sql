-- Human-confirmed identity links; no automatic name-only matching.
create table public.planning_center_match_audit (
 id uuid primary key default extensions.gen_random_uuid(),
 church_id uuid not null references public.churches(id),
 person_id uuid references public.people(id) on delete set null,
 external_id text not null,
 actor_id uuid references auth.users(id) on delete set null,
 previous_contact jsonb not null,
 refreshed_contact jsonb not null,
 created_at timestamptz not null default now()
);
alter table public.planning_center_match_audit enable row level security;
revoke all on public.planning_center_match_audit from public,anon,authenticated;
grant select on public.planning_center_match_audit to authenticated;
grant all on public.planning_center_match_audit to service_role;
create policy matching_audit_admin_read on public.planning_center_match_audit for select to authenticated
 using(private.has_church_role(church_id,array['admin']));
create index matching_audit_person on public.planning_center_match_audit(person_id);
create index matching_audit_actor on public.planning_center_match_audit(actor_id);
create index matching_audit_church_person on public.planning_center_match_audit(church_id,person_id,created_at desc);

create function private.planning_center_matching(p_summary boolean default false) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor public.profiles; run public.import_runs; total bigint; begin
 select * into actor from public.profiles where user_id=auth.uid();
 if actor.user_id is null or actor.church_id is null or not private.has_church_role(actor.church_id,array['admin']) then raise exception 'Administrator access required.'; end if;
 if not exists(select 1 from private.planning_center_connections where church_id=actor.church_id) then return jsonb_build_object('connected',false); end if;
 select count(*) into total from public.people p where p.church_id=actor.church_id and not exists(select 1 from public.person_external_ids e where e.church_id=p.church_id and e.person_id=p.id and e.source_system='planning_center');
 if p_summary then return jsonb_build_object('connected',true,'unlinked_count',total); end if;
 select * into run from public.import_runs where church_id=actor.church_id and source_type='planning_center' and status in ('completed','completed_with_conflicts') order by completed_at desc limit 1;
 return jsonb_build_object('connected',true,'unlinked_count',total,'synced_at',run.completed_at,
 'people',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'first_name',p.first_name,'middle_name',p.middle_name,'last_name',p.last_name,'preferred_name',p.preferred_name,'suffix',p.suffix,'address_line_1',p.address_line_1,'address_line_2',p.address_line_2,'city',p.city,'state_region',p.state_region,'postal_code',p.postal_code,'country_code',p.country_code,'membership_status',p.membership_status,'email',p.email,'mobile_phone',p.mobile_phone,'home_phone',p.home_phone,'is_active',p.is_active,'updated_at',p.updated_at) order by p.last_name,p.first_name) from public.people p where p.church_id=actor.church_id and not exists(select 1 from public.person_external_ids e where e.church_id=p.church_id and e.person_id=p.id and e.source_system='planning_center')),'[]'::jsonb),
 'candidates',coalesce((select jsonb_agg(jsonb_build_object('external_id',r.source_external_id,'first_name',r.raw_record->>'first_name','middle_name',r.raw_record->>'middle_name','last_name',r.raw_record->>'last_name','email',r.raw_record->>'email','mobile_phone',r.raw_record->>'mobile_phone','home_phone',r.raw_record->>'home_phone','is_active',coalesce((r.raw_record->>'is_active')::boolean,true),'source_updated_at',r.raw_record->>'source_updated_at','linked_person_id',e.person_id,'linked_person_name',concat_ws(' ',p.first_name,p.last_name)) order by r.raw_record->>'last_name',r.raw_record->>'first_name') from public.import_rows r left join public.person_external_ids e on e.church_id=r.church_id and e.source_system='planning_center' and e.external_id=r.source_external_id left join public.people p on p.id=e.person_id and p.church_id=e.church_id where r.church_id=actor.church_id and r.import_run_id=run.id and r.source_external_id is not null),'[]'::jsonb));
end;$$;
revoke all on function private.planning_center_matching(boolean) from public,anon;
grant execute on function private.planning_center_matching(boolean) to authenticated;
create function public.planning_center_matching(p_summary boolean default false) returns jsonb
language sql stable security invoker set search_path='' as $$ select private.planning_center_matching(p_summary) $$;
revoke all on function public.planning_center_matching(boolean) from public,anon;
grant execute on function public.planning_center_matching(boolean) to authenticated;

-- Only the verified Edge Function may supply the freshly fetched PCO record.
create function public.link_planning_center_contact(p_actor_id uuid,p_person_id uuid,p_external_id text,p_record jsonb,p_expected_updated_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor public.profiles; person public.people; refreshed public.people; result jsonb; begin
 select * into actor from public.profiles where user_id=p_actor_id;
 if actor.user_id is null or actor.app_role<>'admin' or actor.access_disabled or actor.must_change_password or actor.church_id is null or not exists(select 1 from public.churches where id=actor.church_id and is_active) then raise exception 'Administrator access required.'; end if;
 if not exists(select 1 from private.planning_center_connections where church_id=actor.church_id) then raise exception 'Connect Planning Center before matching contacts.'; end if;
 if p_external_id is null or p_external_id !~ '^[0-9]{1,20}$' or jsonb_typeof(p_record) is distinct from 'object' or nullif(btrim(p_record->>'first_name'),'') is null or nullif(btrim(p_record->>'last_name'),'') is null then raise exception 'Choose a valid Planning Center profile.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor.church_id::text||':pco-match:'||p_external_id,0));
 select * into person from public.people where id=p_person_id and church_id=actor.church_id for update;
 if person.id is null then raise exception 'This contact is not in your church.'; end if;
 if person.updated_at is distinct from p_expected_updated_at then raise exception 'This contact changed. Refresh and review the comparison again.'; end if;
 if exists(select 1 from public.person_external_ids where church_id=actor.church_id and source_system='planning_center' and (person_id=person.id or external_id=p_external_id)) then raise exception 'One of these contacts is already linked. Review the existing link; duplicate records are not merged automatically.'; end if;
 insert into public.person_external_ids(church_id,person_id,source_system,external_id,source_payload,source_updated_at) values(actor.church_id,person.id,'planning_center',p_external_id,p_record,nullif(p_record->>'source_updated_at','')::timestamptz);
 select public.sync_planning_center_person_for_church(actor.church_id,p_external_id,p_record,null,null) into result;
 if result->>'person_id' is distinct from person.id::text or result->>'outcome' is null or result->>'outcome' not in ('updated','unchanged') then raise exception 'The contact could not be linked. No changes were saved.'; end if;
 select * into refreshed from public.people where id=person.id;
 insert into public.planning_center_match_audit(church_id,person_id,external_id,actor_id,previous_contact,refreshed_contact)
 values(actor.church_id,person.id,p_external_id,actor.user_id,
 jsonb_build_object('name',concat_ws(' ',person.first_name,person.last_name),'email',person.email,'mobile_phone',person.mobile_phone,'home_phone',person.home_phone,'is_active',person.is_active),
 jsonb_build_object('name',concat_ws(' ',refreshed.first_name,refreshed.last_name),'email',refreshed.email,'mobile_phone',refreshed.mobile_phone,'home_phone',refreshed.home_phone,'is_active',refreshed.is_active));
 update public.import_conflicts c set resolution='merge',resolved_by=actor.user_id,resolved_at=now() where c.church_id=actor.church_id and person.id=any(c.candidate_person_ids) and c.resolved_at is null and exists(select 1 from public.import_rows r where r.id=c.import_row_id and r.church_id=c.church_id and r.source_external_id=p_external_id);
 return jsonb_build_object('person_id',person.id,'external_id',p_external_id,'linked',true);
end;$$;
revoke all on function public.link_planning_center_contact(uuid,uuid,text,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function public.link_planning_center_contact(uuid,uuid,text,jsonb,timestamptz) to service_role;
