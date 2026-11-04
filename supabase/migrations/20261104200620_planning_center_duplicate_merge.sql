-- Explicit same-church admin review. Original records are retained in private
-- merge history before consolidation; existing applied migrations are unchanged.
create table public.person_merge_audit (
 id uuid primary key default extensions.gen_random_uuid(),
 church_id uuid not null references public.churches(id),
 survivor_id uuid references public.people(id) on delete set null,
 removed_person_id uuid not null,
 actor_id uuid references auth.users(id) on delete set null,
 actor_name text not null,
 snapshot jsonb not null,
 choices jsonb not null,
 created_at timestamptz not null default now()
);
alter table public.person_merge_audit enable row level security;
revoke all on public.person_merge_audit from public,anon,authenticated;
grant select on public.person_merge_audit to authenticated;
grant all on public.person_merge_audit to service_role;
create policy person_merge_audit_admin_read on public.person_merge_audit for select to authenticated using(private.has_church_role(church_id,array['admin']));
create index person_merge_audit_church on public.person_merge_audit(church_id,created_at desc);
create index person_merge_audit_survivor on public.person_merge_audit(survivor_id);
create index person_merge_audit_actor on public.person_merge_audit(actor_id);

create function private.person_merge_snapshot(p_church uuid,p_source uuid,p_target uuid) returns jsonb
language sql stable security invoker set search_path='' as $$
 select jsonb_build_object(
 'people',coalesce((select jsonb_agg(to_jsonb(p) order by p.id) from public.people p where p.church_id=p_church and p.id in(p_source,p_target)),'[]'::jsonb),
 'assignments',coalesce((select jsonb_agg(to_jsonb(a)||jsonb_build_object('ministry',r.name,'position',s.name,'term',t.name,'term_end',t.end_date) order by a.id) from public.assignments a join public.roles r on r.id=a.role_id left join public.sub_roles s on s.id=a.sub_role_id left join public.terms t on t.id=a.term_id where a.church_id=p_church and a.person_id in(p_source,p_target)),'[]'::jsonb),
 'candidates',coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('ministry',r.name,'position',s.name,'caller_name',staff.display_name) order by c.id) from public.placement_candidates c join public.placement_openings o on o.id=c.opening_id join public.roles r on r.id=o.role_id left join public.sub_roles s on s.id=o.sub_role_id left join public.profiles staff on staff.user_id=c.assigned_to where c.church_id=p_church and c.person_id in(p_source,p_target)),'[]'::jsonb),
 'calls',coalesce((select jsonb_agg(to_jsonb(h) order by h.id) from public.volunteer_contact_history h where h.church_id=p_church and h.person_id in(p_source,p_target)),'[]'::jsonb),
 'external_ids',coalesce((select jsonb_agg(to_jsonb(e) order by e.id) from public.person_external_ids e where e.church_id=p_church and e.person_id in(p_source,p_target)),'[]'::jsonb),
 'assignment_external_ids',coalesce((select jsonb_agg(to_jsonb(e) order by e.id) from public.assignment_external_ids e join public.assignments a on a.id=e.assignment_id where a.church_id=p_church and a.person_id in(p_source,p_target)),'[]'::jsonb),
 'discovery',coalesce((select jsonb_agg(to_jsonb(d) order by d.id) from public.discovery_memberships d where d.church_id=p_church and d.person_id in(p_source,p_target)),'[]'::jsonb),
 'staff_links',coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,'person_id',p.person_id) order by p.user_id) from public.profiles p where p.church_id=p_church and p.person_id in(p_source,p_target)),'[]'::jsonb),
 'import_links',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'person_id',r.person_id,'assignment_id',r.assignment_id) order by r.id) from public.import_rows r where r.church_id=p_church and r.person_id in(p_source,p_target)),'[]'::jsonb),
 'conflicts',coalesce((select jsonb_agg(to_jsonb(c) order by c.id) from public.import_conflicts c where c.church_id=p_church and (p_source=any(c.candidate_person_ids) or p_target=any(c.candidate_person_ids))),'[]'::jsonb));
$$;
revoke all on function private.person_merge_snapshot(uuid,uuid,uuid) from public,anon,authenticated;

create function public.review_planning_center_duplicate(p_actor_id uuid,p_person_id uuid,p_external_id text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare actor public.profiles; target uuid; snapshot jsonb; blockers jsonb:='[]'; begin
 select * into actor from public.profiles where user_id=p_actor_id;
 if actor.user_id is null or actor.app_role<>'admin' or actor.access_disabled or actor.must_change_password or actor.church_id is null or not exists(select 1 from public.churches where id=actor.church_id and is_active) then raise exception 'Administrator access required.'; end if;
 if not exists(select 1 from private.planning_center_connections where church_id=actor.church_id) then raise exception 'Connect Planning Center before matching contacts.'; end if;
 if not exists(select 1 from public.people where id=p_person_id and church_id=actor.church_id) then raise exception 'This contact is not in your church.'; end if;
 select person_id into target from public.person_external_ids where church_id=actor.church_id and source_system='planning_center' and external_id=p_external_id;
 if target is null or target=p_person_id then raise exception 'The Planning Center link changed. Choose the contact again.'; end if;
 if exists(select 1 from public.person_external_ids where church_id=actor.church_id and person_id=p_person_id and source_system='planning_center') then raise exception 'The app contact is already linked to Planning Center. Choose it again.'; end if;
 snapshot:=private.person_merge_snapshot(actor.church_id,p_person_id,target);
 if jsonb_array_length(snapshot->'discovery')>1 then blockers:=blockers||jsonb_build_array('Both contacts have separate Ministry Discovery accounts. These accounts must be reviewed by support before merging, so neither assessment history nor account access is lost.'); end if;
 return jsonb_build_object('source_id',p_person_id,'target_id',target,'snapshot',snapshot,'merge_revision',md5(snapshot::text),'blockers',blockers);
end;$$;
revoke all on function public.review_planning_center_duplicate(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.review_planning_center_duplicate(uuid,uuid,text) to service_role;

create function private.merge_contact_notes(a text,b text) returns text language sql immutable set search_path='' as $$
 select case when nullif(a,'') is null then b when nullif(b,'') is null or a=b then a else a||E'\n\n'||b end;
$$;
revoke all on function private.merge_contact_notes(text,text) from public,anon,authenticated;

create function public.merge_planning_center_duplicate(p_actor_id uuid,p_person_id uuid,p_external_id text,p_record jsonb,p_merge_revision text,p_choices jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor public.profiles; review jsonb; snapshot jsonb; target uuid; original public.people; retained public.people;
 a public.assignments; other public.assignments; chosen public.assignments;
 c public.placement_candidates; duplicate public.placement_candidates; preferred public.placement_candidates;
 choice text; result jsonb; audit_id uuid;
begin
 -- The same lock as confirmed linking, followed by a consistent person order.
 select * into actor from public.profiles where user_id=p_actor_id;
 if actor.user_id is null or actor.app_role<>'admin' or actor.access_disabled or actor.must_change_password or actor.church_id is null or not exists(select 1 from public.churches where id=actor.church_id and is_active) then raise exception 'Administrator access required.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor.church_id::text||':pco-match:'||coalesce(p_external_id,''),0));
 select person_id into target from public.person_external_ids where church_id=actor.church_id and source_system='planning_center' and external_id=p_external_id;
 perform 1 from public.people where church_id=actor.church_id and id in(p_person_id,target) order by id for update;
 perform 1 from public.assignments where church_id=actor.church_id and person_id in(p_person_id,target) order by id for update;
 perform 1 from public.placement_candidates where church_id=actor.church_id and person_id in(p_person_id,target) order by id for update;
 perform 1 from public.volunteer_contact_history where church_id=actor.church_id and person_id in(p_person_id,target) order by id for update;
 perform 1 from public.person_external_ids where church_id=actor.church_id and person_id in(p_person_id,target) order by id for update;
 perform 1 from public.discovery_memberships where church_id=actor.church_id and person_id in(p_person_id,target) order by id for update;
 review:=public.review_planning_center_duplicate(p_actor_id,p_person_id,p_external_id);
 if review->>'target_id' is distinct from target::text or review->>'merge_revision' is distinct from p_merge_revision then raise exception 'These records changed. Select the Planning Center profile again to review the latest details.'; end if;
 if jsonb_array_length(review->'blockers')>0 then raise exception '%',review->'blockers'->>0; end if;
 if jsonb_typeof(p_choices) is distinct from 'object' then raise exception 'Review overlapping entries before merging.'; end if;
 if p_external_id !~ '^[0-9]{1,20}$' or jsonb_typeof(p_record) is distinct from 'object' or nullif(btrim(p_record->>'first_name'),'') is null or nullif(btrim(p_record->>'last_name'),'') is null then raise exception 'Choose a valid Planning Center profile.'; end if;
 snapshot:=review->'snapshot';
 select * into original from public.people where id=p_person_id;
 select * into retained from public.people where id=target;
 insert into public.person_merge_audit(church_id,survivor_id,removed_person_id,actor_id,actor_name,snapshot,choices)
 values(actor.church_id,target,p_person_id,actor.user_id,coalesce(actor.display_name,'Administrator'),snapshot,p_choices) returning id into audit_id;
 -- Consolidate only exact ministry/position/term overlaps. Non-overlaps keep IDs.
 for a in select * from public.assignments where person_id=p_person_id and church_id=actor.church_id order by id loop
  select * into other from public.assignments where person_id=target and church_id=actor.church_id and role_id=a.role_id and sub_role_id is not distinct from a.sub_role_id and term_id is not distinct from a.term_id;
  if other.id is null then update public.assignments set person_id=target where id=a.id;
  else
   choice:=p_choices->'assignments'->>a.id::text;
   if choice is null or choice not in(a.id::text,other.id::text) then raise exception 'Choose the current status for each overlapping ministry assignment.'; end if;
   if choice=a.id::text then chosen:=a; else chosen:=other; end if;
   update public.assignments set status=chosen.status,vote_date=chosen.vote_date,archived_at=chosen.archived_at,first_reading_published=chosen.first_reading_published,
    notes=private.merge_contact_notes(other.notes,a.notes),note_is_public=other.note_is_public and a.note_is_public,is_public=other.is_public and a.is_public where id=other.id;
   update public.assignment_external_ids set assignment_id=other.id where assignment_id=a.id and church_id=actor.church_id;
   update public.import_rows set assignment_id=other.id where assignment_id=a.id and church_id=actor.church_id;
   update public.placement_candidates set assignment_id=other.id where assignment_id=a.id and church_id=actor.church_id;
   delete from public.assignments where id=a.id and church_id=actor.church_id;
  end if;
 end loop;
 for c in select * from public.placement_candidates where person_id=p_person_id and church_id=actor.church_id order by id loop
  select * into duplicate from public.placement_candidates where person_id=target and church_id=actor.church_id and opening_id=c.opening_id;
  if duplicate.id is null then update public.placement_candidates set person_id=target where id=c.id;
  else
   choice:=p_choices->'candidates'->>c.id::text;
   if choice is null or choice not in(c.id::text,duplicate.id::text) then raise exception 'Choose the current status for each overlapping placement.'; end if;
   if choice=c.id::text then preferred:=c; else preferred:=duplicate; end if;
   update public.placement_candidates set assigned_to=preferred.assigned_to,response=preferred.response,follow_up=preferred.follow_up,stage=preferred.stage,nominated_on=preferred.nominated_on,first_reading=preferred.first_reading,second_reading=preferred.second_reading,decision_on=preferred.decision_on,requires_vote=preferred.requires_vote,assignment_id=preferred.assignment_id where id=duplicate.id;
   update public.volunteer_contact_history set candidate_id=duplicate.id where candidate_id=c.id and church_id=actor.church_id;
   delete from public.placement_candidates where id=c.id and church_id=actor.church_id;
  end if;
 end loop;
 update public.volunteer_contact_history set person_id=target where person_id=p_person_id and church_id=actor.church_id;
 update public.person_external_ids set person_id=target where person_id=p_person_id and church_id=actor.church_id;
 update public.discovery_memberships set person_id=target where person_id=p_person_id and church_id=actor.church_id;
 update public.profiles set person_id=target where person_id=p_person_id and church_id=actor.church_id;
 update public.import_rows set person_id=target where person_id=p_person_id and church_id=actor.church_id;
 update public.planning_center_match_audit set person_id=target where person_id=p_person_id and church_id=actor.church_id;
 update public.person_merge_audit set survivor_id=target where survivor_id=p_person_id and church_id=actor.church_id;
 update public.import_conflicts set candidate_person_ids=array(select distinct unnest(array_replace(candidate_person_ids,p_person_id,target))) where church_id=actor.church_id and p_person_id=any(candidate_person_ids);
 update public.import_conflicts conflict set resolution='merge',resolved_by=actor.user_id,resolved_at=now()
 where conflict.church_id=actor.church_id and conflict.resolved_at is null and target=any(conflict.candidate_person_ids)
 and exists(select 1 from public.import_rows r where r.id=conflict.import_row_id and r.church_id=actor.church_id and r.source_external_id=p_external_id);
 update public.people set notes=private.merge_contact_notes(retained.notes,original.notes),is_ordained_deacon=retained.is_ordained_deacon or original.is_ordained_deacon,is_ordained_deaconess=retained.is_ordained_deaconess or original.is_ordained_deaconess,is_ordained_elder=retained.is_ordained_elder or original.is_ordained_elder,is_public=retained.is_public and original.is_public where id=target;
 -- The existing PCO-linked person is retained, so future syncs keep one identity.
 select public.sync_planning_center_person_for_church(actor.church_id,p_external_id,p_record,null,null) into result;
 if result->>'person_id' is distinct from target::text or result->>'outcome' is null or result->>'outcome' not in('updated','unchanged') then raise exception 'The merge could not finish. No changes were saved.'; end if;
 delete from public.people where id=p_person_id and church_id=actor.church_id;
 return jsonb_build_object('person_id',target,'external_id',p_external_id,'merged',true,'audit_id',audit_id);
end;$$;
revoke all on function public.merge_planning_center_duplicate(uuid,uuid,text,jsonb,text,jsonb) from public,anon,authenticated;
grant execute on function public.merge_planning_center_duplicate(uuid,uuid,text,jsonb,text,jsonb) to service_role;
