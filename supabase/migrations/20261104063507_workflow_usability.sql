alter table public.profiles add column first_name text;
alter table public.profiles add column last_name text;
alter table public.profiles add column phone text;
alter table public.profiles add column person_id uuid references public.people(id) on delete set null;
create index people_activation_recent_idx on public.people(church_id,source_created_at desc) where is_active and source_created_at is not null;
create index profiles_person_idx on public.profiles(person_id);
-- Link only an unambiguous same-church email; never claim a household match.
create function private.fill_staff_identity() returns trigger language plpgsql security definer set search_path='' as $$
declare mail text; match public.people; n int;
begin
 select lower(btrim(email)) into mail from auth.users where id=new.user_id;
 if new.church_id is not null and new.person_id is null and mail is not null then
  select count(*) into n from public.people where church_id=new.church_id and lower(btrim(email))=mail and is_active;
  if n=1 then
   select * into match from public.people where church_id=new.church_id and lower(btrim(email))=mail and is_active;
   new.person_id:=match.id; new.first_name:=match.first_name; new.last_name:=match.last_name; new.phone:=coalesce(match.mobile_phone,match.home_phone);
  end if;
 end if;
 if new.person_id is not null and not exists(select 1 from public.people where id=new.person_id and church_id=new.church_id) then raise exception 'The linked contact must belong to this church.'; end if;
 if nullif(btrim(new.first_name),'') is not null and nullif(btrim(new.last_name),'') is not null then
  new.display_name:=btrim(new.first_name)||' '||btrim(new.last_name);
 end if;
 return new;
end;$$;
revoke all on function private.fill_staff_identity() from public,anon,authenticated;
create trigger profiles_fill_staff_identity before insert or update on public.profiles for each row execute function private.fill_staff_identity();
update public.profiles set display_name=display_name where church_id is not null;

create function private.complete_staff_profile(p_first_name text,p_last_name text,p_phone text) returns void language plpgsql security definer set search_path='' as $$
declare p public.profiles; mail text; matches integer; linked uuid;
begin
 select * into p from public.profiles where user_id=auth.uid() for update;
 if p.user_id is null or p.church_id is null or p.access_disabled or not exists(select 1 from public.churches where id=p.church_id and is_active) then raise exception 'An active church account is required.'; end if;
 if length(btrim(coalesce(p_first_name,''))) not between 1 and 100 or length(btrim(coalesce(p_last_name,''))) not between 1 and 100 then raise exception 'Enter your first and last name (up to 100 characters each).'; end if;
 if (p.person_id is null and length(btrim(coalesce(p_phone,''))) not between 5 and 50) or length(coalesce(p_phone,''))>50 then raise exception 'Enter a phone number between 5 and 50 characters.'; end if;
 linked:=p.person_id;
 if linked is null then
  select lower(btrim(email)) into mail from auth.users where id=auth.uid();
  select count(*) into matches from public.people where church_id=p.church_id and lower(btrim(email))=mail and is_active;
  if matches=0 then
   insert into public.people(church_id,first_name,last_name,email,mobile_phone,is_active,is_public)
   values(p.church_id,btrim(p_first_name),btrim(p_last_name),mail,nullif(btrim(p_phone),''),true,false) returning id into linked;
  end if;
 end if;
 update public.profiles set first_name=btrim(p_first_name),last_name=btrim(p_last_name),phone=nullif(btrim(p_phone),''),person_id=linked where user_id=auth.uid();
end;$$;
revoke all on function private.complete_staff_profile(text,text,text) from public,anon;
grant execute on function private.complete_staff_profile(text,text,text) to authenticated;
create function public.complete_staff_profile(p_first_name text,p_last_name text,p_phone text) returns void language sql security invoker set search_path='' as $$select private.complete_staff_profile(p_first_name,p_last_name,p_phone)$$;
revoke all on function public.complete_staff_profile(text,text,text) from public,anon;
grant execute on function public.complete_staff_profile(text,text,text) to authenticated;

create table public.church_focus_settings (
 church_id uuid primary key references public.churches(id),
 membership_types text[] not null default '{}',
 activation_statuses text[] not null default '{}'
);
alter table public.church_focus_settings enable row level security;
revoke all on public.church_focus_settings from public,anon,authenticated;
grant select on public.church_focus_settings to authenticated;
grant all on public.church_focus_settings to service_role;
create policy focus_settings_read on public.church_focus_settings for select to authenticated using(private.has_church_role(church_id,array['admin','editor','viewer']));
insert into public.church_focus_settings(church_id,activation_statuses) select id,case when slug='riverview' then array['riverview member'] else '{}'::text[] end from public.churches;

create function private.save_focus_memberships(p_statuses text[]) returns void language plpgsql security definer set search_path='' as $$
declare c uuid:=private.current_church_id();
begin
 if not private.has_church_role(c,array['admin']) then raise exception 'Administrator access required.'; end if;
 if p_statuses is null or cardinality(p_statuses)>100 then raise exception 'Choose up to 100 membership types.'; end if;
 insert into public.church_focus_settings(church_id,activation_statuses) values(c,p_statuses) on conflict(church_id) do update set activation_statuses=excluded.activation_statuses;
end;$$;
revoke all on function private.save_focus_memberships(text[]) from public,anon;
grant execute on function private.save_focus_memberships(text[]) to authenticated;
create function public.save_focus_memberships(p_statuses text[]) returns void language sql security invoker set search_path='' as $$select private.save_focus_memberships(p_statuses)$$;
revoke all on function public.save_focus_memberships(text[]) from public,anon;
grant execute on function public.save_focus_memberships(text[]) to authenticated;

create function public.cache_pco_membership_types(p_church_id uuid,p_values text[]) returns void language sql security invoker set search_path='' as $$
 insert into public.church_focus_settings(church_id,membership_types) values(p_church_id,p_values) on conflict(church_id) do update set membership_types=excluded.membership_types;
$$;
revoke all on function public.cache_pco_membership_types(uuid,text[]) from public,anon,authenticated;
grant execute on function public.cache_pco_membership_types(uuid,text[]) to service_role;

create function public.focus_preferences() returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('selected',coalesce((select activation_statuses from public.church_focus_settings where church_id=private.current_church_id()),'{}'::text[]),
 'options',(select coalesce(jsonb_agg(v order by v),'[]'::jsonb) from (select unnest(membership_types) v from public.church_focus_settings where church_id=private.current_church_id() union select distinct membership_status from public.people where church_id=private.current_church_id() and source_created_at is not null and membership_status is not null) available where v<>''));
$$;
revoke all on function public.focus_preferences() from public,anon;
grant execute on function public.focus_preferences() to authenticated;
create function public.volunteer_activation() returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(picked)),'[]'::jsonb) from (
 select p.* from public.people p where p.church_id=private.current_church_id() and p.is_active and p.source_created_at is not null
 and exists(select 1 from public.person_external_ids e where e.person_id=p.id and e.source_system='planning_center')
 and (not exists(select 1 from public.church_focus_settings s where s.church_id=p.church_id and cardinality(s.activation_statuses)>0) or lower(btrim(p.membership_status))=any(select lower(btrim(x)) from public.church_focus_settings s cross join lateral unnest(s.activation_statuses) x where s.church_id=p.church_id))
 and not exists(select 1 from public.assignments a join public.roles r on r.id=a.role_id left join public.terms t on t.id=a.term_id where a.person_id=p.id and a.church_id=p.church_id and a.status='active' and r.is_active and (t.end_date is null or t.end_date>=current_date))
 order by p.source_created_at desc,p.last_name,p.id limit 100) picked;
$$;
revoke all on function public.volunteer_activation() from public,anon;
grant execute on function public.volunteer_activation() to authenticated;

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
   if c.stage<>'nominated' or on_date<c.nominated_on then raise exception 'Record nomination before first reading.'; end if;
   update public.placement_candidates set stage='first_reading',first_reading=on_date where id=c.id;
  elsif p_action='second_reading' then
   if c.stage<>'first_reading' or on_date<=c.first_reading then raise exception 'Second reading must follow first reading on a later date.'; end if;
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
   if p_action<>'appoint' and (c.stage<>'second_reading' or on_date<c.second_reading) then raise exception 'Record both readings before the vote.'; end if;
   if p_action='vote_failed' then
    update public.placement_candidates set stage='not_elected',decision_on=on_date,follow_up=null where id=c.id;
   else
    if c.response<>'yes' then raise exception 'Confirm current willingness before activation.'; end if;
    insert into public.assignments(church_id,person_id,role_id,sub_role_id,term_id,vote_date,status,is_public)
    values(actor.church_id,c.person_id,o.role_id,o.sub_role_id,o.term_id,case when p_action='vote_passed' then on_date else null end,'active',true) returning id into result_id;
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
