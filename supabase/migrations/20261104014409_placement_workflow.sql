-- Recruitment is separate from active assignments. All writes use the checked
-- command below; direct client mutations are intentionally unavailable.
create table public.placement_openings (
 id uuid primary key default gen_random_uuid(),
 church_id uuid not null references public.churches(id),
 role_id uuid not null references public.roles(id),
 sub_role_id uuid references public.sub_roles(id),
 term_id uuid references public.terms(id),
 quantity integer not null default 1 check(quantity between 1 and 100),
 status text not null default 'open' check(status in ('open','filled','cancelled')),
 notes text not null default '',
 created_at timestamptz not null default now()
);
create table public.placement_candidates (
 id uuid primary key default gen_random_uuid(),
 church_id uuid not null references public.churches(id),
 opening_id uuid not null references public.placement_openings(id),
 person_id uuid not null references public.people(id),
 assigned_to uuid references public.profiles(user_id) on delete set null,
 response text not null default 'considering' check(response in ('considering','yes','no','maybe_later','no_answer','message_left','other')),
 follow_up date,
 stage text not null default 'considering' check(stage in ('considering','nominated','first_reading','second_reading','deferred','elected','appointed','withdrawn','not_elected')),
 nominated_on date,
 first_reading date,
 second_reading date,
 decision_on date,
 requires_vote boolean,
 assignment_id uuid references public.assignments(id),
 created_at timestamptz not null default now(),
 unique(opening_id,person_id)
);
create table public.volunteer_contact_history (
 id uuid primary key default gen_random_uuid(),
 church_id uuid not null references public.churches(id),
 candidate_id uuid not null references public.placement_candidates(id),
 person_id uuid not null references public.people(id),
 kind text not null,
 happened_on date not null,
 response text,
 notes text not null default '',
 follow_up date,
 caller_id uuid references public.profiles(user_id) on delete set null,
 caller_name text,
 recorded_by uuid references public.profiles(user_id) on delete set null,
 recorder_name text not null,
 role_label text not null,
 created_at timestamptz not null default now()
);
create index placement_openings_church on public.placement_openings(church_id);
create index placement_openings_role on public.placement_openings(role_id);
create index placement_openings_position on public.placement_openings(sub_role_id);
create index placement_openings_term on public.placement_openings(term_id);
create index placement_candidates_assignment on public.placement_candidates(assignment_id);
create index placement_candidates_church on public.placement_candidates(church_id);
create index placement_candidates_calls on public.placement_candidates(assigned_to,follow_up);
create index placement_candidates_person on public.placement_candidates(person_id);
create index volunteer_history_person on public.volunteer_contact_history(church_id,person_id,created_at desc);
create index volunteer_history_candidate on public.volunteer_contact_history(candidate_id);
create index volunteer_history_caller on public.volunteer_contact_history(caller_id);
create index volunteer_history_recorder on public.volunteer_contact_history(recorded_by);
alter table public.placement_openings enable row level security;
alter table public.placement_candidates enable row level security;
alter table public.volunteer_contact_history enable row level security;
create policy placement_openings_read on public.placement_openings for select to authenticated using(private.has_church_role(church_id,array['admin','editor','viewer']));
create policy placement_candidates_read on public.placement_candidates for select to authenticated using(private.has_church_role(church_id,array['admin','editor','viewer']));
create policy volunteer_history_read on public.volunteer_contact_history for select to authenticated using(private.has_church_role(church_id,array['admin','editor','viewer']));
revoke all on public.placement_openings,public.placement_candidates,public.volunteer_contact_history from public,anon,authenticated;
grant select on public.placement_openings,public.placement_candidates,public.volunteer_contact_history to authenticated;
grant all on public.placement_openings,public.placement_candidates,public.volunteer_contact_history to service_role;

-- Minimal same-church staff directory, without exposing authentication records.
create function private.placement_staff() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('user_id',p.user_id,'display_name',coalesce(nullif(p.display_name,''),'Staff '||left(p.user_id::text,8)),'app_role',p.app_role) order by p.display_name),'[]'::jsonb)
 from public.profiles p where p.church_id=private.current_church_id()
 and not p.access_disabled and not p.must_change_password and p.app_role in ('admin','editor');
$$;
revoke all on function private.placement_staff() from public,anon;
grant execute on function private.placement_staff() to authenticated;
create function public.placement_staff() returns jsonb language sql stable security invoker set search_path='' as $$select private.placement_staff()$$;
revoke all on function public.placement_staff() from public,anon;
grant execute on function public.placement_staff() to authenticated;

create function private.placement_command(p_action text,p_data jsonb) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 actor public.profiles; o public.placement_openings; c public.placement_candidates;
 r public.roles; s public.sub_roles; t public.terms; person public.people; caller public.profiles;
 result_id uuid; on_date date:=coalesce(nullif(p_data->>'date','')::date,current_date);
 staff_id uuid; event_kind text:=p_action; event_notes text:=coalesce(p_data->>'notes','');
 requirement boolean; occupied integer; final_stage text;
begin
 select * into actor from public.profiles where user_id=auth.uid();
 if actor.user_id is null or actor.church_id is null or actor.access_disabled or actor.must_change_password or actor.app_role not in ('admin','editor') then
  raise exception 'Administrator or editor access required.'; end if;
 if on_date>current_date then raise exception 'Record an actual date, not a future date.'; end if;
 if length(event_notes)>10000 then raise exception 'Notes must be at most 10000 characters.'; end if;
 if p_action='opening' then
  select * into r from public.roles where id=(p_data->>'role_id')::uuid and church_id=actor.church_id and is_active;
  if not found then raise exception 'Choose an active ministry in your church.'; end if;
  if nullif(p_data->>'sub_role_id','') is not null then
   select * into s from public.sub_roles where id=(p_data->>'sub_role_id')::uuid and role_id=r.id and church_id=actor.church_id and is_active;
   if not found then raise exception 'Choose a position in this ministry.'; end if;
  end if;
  if nullif(p_data->>'term_id','') is not null then
   select * into t from public.terms where id=(p_data->>'term_id')::uuid and church_id=actor.church_id and is_active;
   if not found then raise exception 'Choose an active term in your church.'; end if;
  end if;
  if s.id is not null and (r.requires_vote or s.requires_vote) and t.id is null then raise exception 'A term is required for this voted position.'; end if;
  insert into public.placement_openings(church_id,role_id,sub_role_id,term_id,quantity,notes)
  values(actor.church_id,r.id,s.id,t.id,coalesce((p_data->>'quantity')::integer,1),event_notes) returning id into result_id;
  return jsonb_build_object('id',result_id);
 end if;
 -- Every mutation for an opening shares its lock, preventing double filling.
 if p_action in ('candidate','cancel_opening') then
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
 if p_action='cancel_opening' then
  if exists(select 1 from public.placement_candidates where opening_id=o.id and stage in ('nominated','first_reading','second_reading','deferred')) then raise exception 'Withdraw pending nominations before closing this opening.'; end if;
  update public.placement_openings set status='cancelled' where id=o.id;
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
   select count(*) into occupied from public.placement_candidates where opening_id=o.id and stage in ('nominated','first_reading','second_reading','deferred','elected','appointed');
   if occupied>=o.quantity then raise exception 'All places are filled or have pending nominees.'; end if;
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
    if (select count(*) from public.placement_candidates where opening_id=o.id and stage in ('elected','appointed'))>=o.quantity then
     update public.placement_openings set status='filled' where id=o.id;
    end if;
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
revoke all on function private.placement_command(text,jsonb) from public,anon;
grant execute on function private.placement_command(text,jsonb) to authenticated;
create function public.placement_command(p_action text,p_data jsonb) returns jsonb language sql security invoker set search_path='' as $$select private.placement_command(p_action,p_data)$$;
revoke all on function public.placement_command(text,jsonb) from public,anon;
grant execute on function public.placement_command(text,jsonb) to authenticated;
