-- Password recovery does not transfer ownership. Existing column grants restrict
-- the reset flag to trusted server operations; owner identity and access stay protected.
create or replace function private.guard_church_owner() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.church_owners where user_id=old.user_id) and
 (tg_op='DELETE' or new.church_id is distinct from old.church_id or new.app_role<>'admin' or new.access_disabled) then
  raise exception 'Transfer church ownership before removing or changing the owner account.';
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end;$$;

create or replace function private.placement_command(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor public.profiles; o public.placement_openings; c public.placement_candidates;
 r public.roles; s public.sub_roles; t public.terms; person public.people; caller public.profiles;
 result_id uuid; on_date date:=coalesce(nullif(p_data->>'date','')::date,current_date);
 staff_id uuid; event_kind text:=p_action; event_notes text:=coalesce(p_data->>'notes','');
 requirement boolean; final_stage text;
begin
 select * into actor from public.profiles where user_id=auth.uid();
 if actor.user_id is null or actor.church_id is null or actor.access_disabled or actor.must_change_password or actor.app_role not in ('admin','editor') or not exists(select 1 from public.churches where id=actor.church_id and is_active) then
  raise exception 'Administrator or editor access required.'; end if;
 if p_action in ('first_reading','unpublish_first_reading') then on_date:=current_date; end if;
 if on_date>current_date then raise exception 'Record an actual date, not a future date.'; end if;
 if length(event_notes)>10000 then raise exception 'Notes must be at most 10000 characters.'; end if;
 if p_action='opening' then
  perform pg_advisory_xact_lock(hashtextextended(actor.church_id::text||':placement-catalog',0));
  if nullif(p_data->>'role_id','') is null then
   if length(btrim(coalesce(p_data->>'new_role_name',''))) not between 1 and 120 then raise exception 'Enter a ministry name between 1 and 120 characters.'; end if;
   select * into r from public.roles where church_id=actor.church_id and lower(btrim(name))=lower(btrim(p_data->>'new_role_name')) and is_active;
   if r.id is null then
    insert into public.roles(church_id,name,requires_vote,is_active,is_public,display_order)
    values(actor.church_id,btrim(p_data->>'new_role_name'),false,true,true,100) returning * into r;
   end if;
   p_data:=p_data||jsonb_build_object('role_id',r.id);
  end if;
  select * into r from public.roles where id=(p_data->>'role_id')::uuid and church_id=actor.church_id and is_active;
  if not found then raise exception 'Choose an active ministry in your church.'; end if;
  if nullif(p_data->>'sub_role_id','') is not null then
   select * into s from public.sub_roles where id=(p_data->>'sub_role_id')::uuid and role_id=r.id and church_id=actor.church_id and is_active;
   if not found then raise exception 'Choose a position in this ministry.'; end if;
  end if;
  if nullif(p_data->>'new_position_name','') is not null then
   if length(btrim(p_data->>'new_position_name')) not between 1 and 120 then raise exception 'Enter a position name between 1 and 120 characters.'; end if;
   select * into s from public.sub_roles where role_id=r.id and church_id=actor.church_id and lower(btrim(name))=lower(btrim(p_data->>'new_position_name')) and is_active;
   if s.id is null then
    insert into public.sub_roles(church_id,role_id,name,requires_vote,is_active,leadership_rank)
    values(actor.church_id,r.id,btrim(p_data->>'new_position_name'),coalesce((p_data->>'new_position_vote')::boolean,false),true,100) returning * into s;
   end if;
  end if;
  if nullif(p_data->>'new_term_name','') is not null then
   if length(btrim(p_data->>'new_term_name')) not between 1 and 120 or nullif(p_data->>'term_start','') is null or nullif(p_data->>'term_end','') is null then raise exception 'Enter a term name, start date and end date.'; end if;
   if (p_data->>'term_start')::date>(p_data->>'term_end')::date then raise exception 'Term end date must be on or after its start date.'; end if;
   select * into t from public.terms where church_id=actor.church_id and lower(btrim(name))=lower(btrim(p_data->>'new_term_name')) and is_active;
   if t.id is null then
    insert into public.terms(church_id,name,start_date,end_date,term_type) values(actor.church_id,btrim(p_data->>'new_term_name'),(p_data->>'term_start')::date,(p_data->>'term_end')::date,'custom') returning * into t;
   end if;
   p_data:=p_data||jsonb_build_object('term_id',t.id);
  end if;
  if nullif(p_data->>'term_id','') is not null then
   select * into t from public.terms where id=(p_data->>'term_id')::uuid and church_id=actor.church_id and is_active;
   if not found then raise exception 'Choose an active term in your church.'; end if;
  end if;
  if s.id is not null and (r.requires_vote or s.requires_vote) and t.id is null then raise exception 'A term is required for this voted position.'; end if;
  if exists(select 1 from public.placement_openings where church_id=actor.church_id and role_id=r.id and sub_role_id is not distinct from s.id and term_id is not distinct from t.id and status='open') then raise exception 'An opening already exists for this ministry, position and term. Open the existing card instead.'; end if;
  insert into public.placement_openings(church_id,role_id,sub_role_id,term_id,quantity,notes)
  values(actor.church_id,r.id,s.id,t.id,1,event_notes) returning id into result_id;
  return jsonb_build_object('id',result_id);
 end if;
 -- Every mutation for an opening shares its lock, preventing double filling.
 if p_action in ('candidate','cancel_opening','finish_opening','restore_opening') then
  select * into o from public.placement_openings where id=(p_data->>'opening_id')::uuid and church_id=actor.church_id for update;
 else
  select * into c from public.placement_candidates where id=(p_data->>'candidate_id')::uuid and church_id=actor.church_id;
  if not found then raise exception 'Candidate not found.'; end if;
  select * into o from public.placement_openings where id=c.opening_id and church_id=actor.church_id for update;
  select * into c from public.placement_candidates where id=c.id for update;
 end if;
 if o.id is null then raise exception 'Opening not found.'; end if;
 -- Lock the person against concurrent deactivation until this action commits.
 if p_action in ('nominate','appoint','vote_passed') then
  select * into person from public.people where id=c.person_id and church_id=actor.church_id and is_active for share;
  if not found then raise exception 'This person is inactive. Reactivate their profile before nomination or appointment.'; end if;
 end if;
 select * into r from public.roles where id=o.role_id and church_id=actor.church_id;
 select * into s from public.sub_roles where id=o.sub_role_id and church_id=actor.church_id;
 if p_action='restore_opening' then
  perform pg_advisory_xact_lock(hashtextextended(actor.church_id::text||':placement-catalog',0));
  if exists(select 1 from public.placement_openings where church_id=actor.church_id and role_id=o.role_id and sub_role_id is not distinct from o.sub_role_id and term_id is not distinct from o.term_id and status='open' and id<>o.id) then raise exception 'Another open card already exists for this ministry, position and term.'; end if;
  update public.placement_openings set status='open' where id=o.id;
  return jsonb_build_object('id',o.id);
 elsif p_action in ('cancel_opening','finish_opening') then
  if exists(select 1 from public.placement_candidates where opening_id=o.id and stage in ('nominated','first_reading','second_reading','deferred')) then raise exception 'Withdraw pending nominations before closing this opening.'; end if;
  update public.placement_openings set status=case when p_action='finish_opening' then 'filled' else 'cancelled' end where id=o.id;
  return jsonb_build_object('id',o.id);
 elsif p_action='candidate' then
  if o.status<>'open' then raise exception 'This opening is closed.'; end if;
  select * into person from public.people where id=(p_data->>'person_id')::uuid and church_id=actor.church_id and is_active;
  if not found then raise exception 'Choose an active person in your church.'; end if;
  insert into public.placement_candidates(church_id,opening_id,person_id) values(actor.church_id,o.id,person.id) returning id into result_id;
  return jsonb_build_object('id',result_id);
 elsif p_action='assign_call' then
  if actor.app_role<>'admin' then raise exception 'Only administrators may assign calls.'; end if;
  if o.status<>'open' or c.stage in ('elected','appointed','withdrawn','not_elected') then raise exception 'This candidate is closed.'; end if;
  staff_id:=nullif(p_data->>'caller_id','')::uuid;
  if staff_id is not null then
   select * into caller from public.profiles where user_id=staff_id and church_id=actor.church_id and app_role in ('admin','editor') and not access_disabled and not must_change_password;
   if not found then raise exception 'Choose an active administrator or editor in your church.'; end if;
  end if;
  update public.placement_candidates set assigned_to=staff_id,follow_up=nullif(p_data->>'follow_up','')::date where id=c.id;
 elsif p_action='call' then
  staff_id:=coalesce(nullif(p_data->>'caller_id','')::uuid,actor.user_id);
  if actor.app_role<>'admin' and staff_id<>actor.user_id then raise exception 'Editors can only record calls they made.'; end if;
  select * into caller from public.profiles where user_id=staff_id and church_id=actor.church_id and app_role in ('admin','editor') and not access_disabled and not must_change_password;
  if not found then raise exception 'Choose an active caller in your church.'; end if;
  if p_data->>'response' is null or p_data->>'response' not in ('yes','no','maybe_later','considering','no_answer','message_left','other') then raise exception 'Choose a response.'; end if;
  if p_data->>'response'='other' and btrim(event_notes)='' then raise exception 'Explain the other response.'; end if;
  if nullif(p_data->>'follow_up','')::date<on_date then raise exception 'Follow-up cannot be before the call.'; end if;
  -- Backdated entries remain in history without overwriting a newer response.
  if not exists(select 1 from public.volunteer_contact_history h where h.candidate_id=c.id and h.kind='call' and h.happened_on>on_date) then
   update public.placement_candidates set response=p_data->>'response',follow_up=nullif(p_data->>'follow_up','')::date where id=c.id;
  end if;
 else
  if c.stage in ('elected','appointed','withdrawn','not_elected') then raise exception 'This candidate is closed.'; end if;
  if o.status<>'open' then raise exception 'This opening is closed.'; end if;
  if not r.is_active then raise exception 'This ministry is archived.'; end if;
  if o.sub_role_id is not null and (s.id is null or not s.is_active) then raise exception 'This position is archived.'; end if;
  requirement:=s.id is not null and (r.requires_vote or s.requires_vote);
  if p_action in ('nominate','appoint') then
   if c.stage<>'considering' or c.response<>'yes' then raise exception 'Record willingness before selecting this candidate.'; end if;
   -- Recruitment stays open until the committee finishes it explicitly.
   if requirement and o.term_id is null then raise exception 'A term is required for this voted position.'; end if;
   if p_action='nominate' and not requirement then raise exception 'This position uses appointment, not nomination.'; end if;
   if p_action='appoint' and requirement then raise exception 'This position requires nomination and church vote.'; end if;
   update public.placement_candidates set requires_vote=requirement,nominated_on=case when requirement then on_date else null end where id=c.id;
  end if;
  if p_action='nominate' then
   update public.placement_candidates set stage='nominated' where id=c.id;
  elsif p_action='first_reading' then
   if c.stage<>'nominated' then raise exception 'Record nomination before first reading.'; end if;
   update public.placement_candidates set stage='first_reading',first_reading=on_date where id=c.id;
  elsif p_action='unpublish_first_reading' then
   if c.stage not in ('first_reading','second_reading') then raise exception 'Only a pending publication may be corrected.'; end if;
   update public.placement_candidates set stage='nominated',first_reading=null,second_reading=null where id=c.id;
  elsif p_action='second_reading' then
   if c.stage<>'first_reading' then raise exception 'Confirm first reading publication before second reading.'; end if;
   update public.placement_candidates set stage='second_reading',second_reading=on_date where id=c.id;
  elsif p_action='defer' then
   if c.stage not in ('nominated','first_reading','second_reading') then raise exception 'Only a pending nomination may be deferred.'; end if;
   update public.placement_candidates set stage='deferred' where id=c.id;
  elsif p_action='resume' then
   if c.stage<>'deferred' then raise exception 'This nomination is not deferred.'; end if;
   update public.placement_candidates set stage=case when second_reading is not null then 'second_reading' when first_reading is not null then 'first_reading' else 'nominated' end where id=c.id;
  elsif p_action='withdraw' then
   update public.placement_candidates set stage='withdrawn',decision_on=on_date,follow_up=null where id=c.id;
  elsif p_action in ('vote_passed','vote_failed','appoint') then
   if p_action<>'appoint' and (c.stage not in ('first_reading','second_reading') or c.first_reading is null or on_date<c.nominated_on) then raise exception 'Confirm first reading publication before recording the vote.'; end if;
   if p_action<>'appoint' then update public.placement_candidates set second_reading=on_date where id=c.id; end if;
   if p_action='vote_failed' then
    update public.placement_candidates set stage='not_elected',decision_on=on_date,follow_up=null where id=c.id;
   else
    if c.response<>'yes' then raise exception 'Confirm current willingness before activation.'; end if;
    insert into public.assignments(church_id,person_id,role_id,sub_role_id,term_id,vote_date,status,is_public,first_reading_published)
    values(actor.church_id,c.person_id,o.role_id,o.sub_role_id,o.term_id,case when p_action='vote_passed' then on_date else null end,'active',true,p_action='vote_passed') returning id into result_id;
    final_stage:=case when p_action='appoint' then 'appointed' else 'elected' end;
    update public.placement_candidates set stage=final_stage,decision_on=on_date,assignment_id=result_id,follow_up=null where id=c.id;

   end if;
  else raise exception 'Unknown placement action.';
  end if;
 end if;
 insert into public.volunteer_contact_history(church_id,candidate_id,person_id,kind,happened_on,response,notes,follow_up,caller_id,caller_name,recorded_by,recorder_name,role_label)
 values(actor.church_id,c.id,c.person_id,event_kind,on_date,case when p_action='call' then p_data->>'response' end,event_notes,nullif(p_data->>'follow_up','')::date,staff_id,
 case when caller.user_id is not null then coalesce(nullif(caller.display_name,''),'Staff '||left(caller.user_id::text,8)) end,
 actor.user_id,coalesce(nullif(actor.display_name,''),'Staff '||left(actor.user_id::text,8)),r.name||coalesce(' · '||s.name,''));
 return jsonb_build_object('id',coalesce(result_id,c.id));
end;
$$;
