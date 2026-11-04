
-- Ministry discovery is separate from invited staff access.
create table private.discovery_settings (
 church_id uuid primary key references public.churches(id) on delete cascade,
 token text not null unique default encode(extensions.gen_random_bytes(32),'hex'),
 enabled boolean not null default true
);
create table private.discovery_versions (
 version text primary key,
 questions jsonb not null,
 created_at timestamptz not null default now()
);
create table public.discovery_memberships (
 id uuid primary key default gen_random_uuid(),
 church_id uuid not null references public.churches(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 person_id uuid,
 first_name text not null check(length(btrim(first_name)) between 1 and 100),
 last_name text not null check(length(btrim(last_name)) between 1 and 100),
 consent_version text not null,
 consent_at timestamptz not null default now(),
 disabled boolean not null default false,
 created_at timestamptz not null default now(),
 unique(user_id,church_id),unique(id,church_id),
 foreign key(person_id,church_id) references public.people(id,church_id) on delete restrict
);
create unique index discovery_one_person on public.discovery_memberships(church_id,person_id) where person_id is not null;
create index discovery_memberships_church on public.discovery_memberships(church_id,created_at);
create table public.discovery_profiles (
 membership_id uuid primary key,
 church_id uuid not null,
 draft jsonb not null default '{}',
 submitted jsonb,
 revision integer not null default 0,
 updated_at timestamptz not null default now(),
 foreign key(membership_id,church_id) references public.discovery_memberships(id,church_id) on delete cascade
);
create table public.discovery_attempts (
 id uuid primary key default gen_random_uuid(),
 membership_id uuid not null,
 church_id uuid not null,
 kind text not null check(kind in ('bigfive','motivations')),
 version text not null references private.discovery_versions(version),
 answers jsonb not null default '{}',
 scores jsonb,
 submitted_at timestamptz,
 revision integer not null default 0,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 foreign key(membership_id,church_id) references public.discovery_memberships(id,church_id) on delete cascade
);
create unique index discovery_one_draft on public.discovery_attempts(membership_id,kind) where submitted_at is null;
create index discovery_attempts_latest on public.discovery_attempts(membership_id,kind,submitted_at desc) where submitted_at is not null;
create table public.discovery_observations (
 id uuid primary key default gen_random_uuid(),
 membership_id uuid not null,
 church_id uuid not null,
 author_id uuid references auth.users(id) on delete set null,
 note text not null check(length(btrim(note)) between 1 and 4000),
 created_at timestamptz not null default now(),
 foreign key(membership_id,church_id) references public.discovery_memberships(id,church_id) on delete cascade
);
create index discovery_observations_member on public.discovery_observations(membership_id,created_at);

create function private.discovery_owner(p_member uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.discovery_memberships m
 join public.churches c on c.id=m.church_id join auth.users u on u.id=m.user_id
 left join public.profiles p on p.user_id=u.id
 where m.id=p_member and m.user_id=(select auth.uid()) and not m.disabled
 and c.is_active and u.email_confirmed_at is not null
 and not coalesce(p.access_disabled,false) and not coalesce(p.must_change_password,false));
$$;
revoke all on function private.discovery_owner(uuid) from public,anon;
grant execute on function private.discovery_owner(uuid) to authenticated;

do $$
declare t text;
begin
 foreach t in array array['discovery_memberships','discovery_profiles','discovery_attempts','discovery_observations'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon,authenticated',t);
 execute format('grant all on public.%I to service_role',t);
 end loop;
end;$$;
grant select on public.discovery_memberships,public.discovery_profiles,public.discovery_attempts to authenticated;
create policy discovery_membership_owner on public.discovery_memberships for select to authenticated using(private.discovery_owner(id));
create policy discovery_profile_owner on public.discovery_profiles for select to authenticated using(private.discovery_owner(membership_id));
create policy discovery_attempt_owner on public.discovery_attempts for select to authenticated using(private.discovery_owner(membership_id));
-- Staff access is through bounded RPCs, so raw answers, drafts and N scores do not leak.

create function public.discovery_registration(p_rotate boolean default false,p_enabled boolean default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c uuid:=private.current_church_id(); s private.discovery_settings;
begin
 if not private.has_church_role(c,array['admin']) then raise exception 'Administrator access required.'; end if;
 insert into private.discovery_settings(church_id) values(c) on conflict do nothing;
 update private.discovery_settings set token=case when p_rotate then encode(extensions.gen_random_bytes(32),'hex') else token end,
 enabled=coalesce(p_enabled,enabled) where church_id=c returning * into s;
 return jsonb_build_object('token',s.token,'enabled',s.enabled,'church_id',s.church_id);
end;$$;

create function public.discovery_public_church(p_token text)
returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',c.id,'name',c.name,'slug',c.slug)
 from private.discovery_settings s join public.churches c on c.id=s.church_id
 where length(p_token)=64 and s.token=p_token and s.enabled and c.is_active;
$$;

create function public.discovery_enroll(p_token text,p_first_name text,p_last_name text,p_consent boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c uuid; m public.discovery_memberships;
begin
 if auth.uid() is null or p_consent is distinct from true then raise exception 'Sign in and accept the sharing notice.'; end if;
 if not exists(select 1 from auth.users u left join public.profiles p on p.user_id=u.id
 where u.id=auth.uid() and u.email_confirmed_at is not null and not coalesce(p.access_disabled,false)
 and not coalesce(p.must_change_password,false)) then raise exception 'A verified, enabled account is required.'; end if;
 select s.church_id into c from private.discovery_settings s join public.churches ch on ch.id=s.church_id
 where s.token=p_token and length(p_token)=64 and s.enabled and ch.is_active;
 if c is null then raise exception 'This church registration link is unavailable.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text||c::text,0));
 insert into public.discovery_memberships(church_id,user_id,first_name,last_name,consent_version)
 values(c,auth.uid(),btrim(p_first_name),btrim(p_last_name),'2026-10-26.1')
 on conflict(user_id,church_id) do nothing;
 select * into m from public.discovery_memberships where church_id=c and user_id=auth.uid();
 if m.disabled then raise exception 'Participant access has been disabled. Contact your church administrator.'; end if;
 insert into public.discovery_profiles(membership_id,church_id) values(m.id,c) on conflict do nothing;
 return to_jsonb(m);
end;$$;

create function public.discovery_workspace(p_church_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m public.discovery_memberships;
begin
 select * into m from public.discovery_memberships where church_id=p_church_id and user_id=auth.uid();
 if m.id is null then return null; end if;
 if not private.discovery_owner(m.id) then raise exception 'Participant access required.'; end if;
 return jsonb_build_object('membership',to_jsonb(m),
 'church',(select jsonb_build_object('id',id,'name',name,'slug',slug) from public.churches where id=m.church_id),
 'profile',(select to_jsonb(p) from public.discovery_profiles p where membership_id=m.id),
 'attempts',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc,a.id) from public.discovery_attempts a where membership_id=m.id),'[]'::jsonb));
end;$$;

create function public.discovery_save_profile(p_member uuid,p_data jsonb,p_revision integer,p_submit boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.discovery_profiles; item jsonb; k text;
begin
 if not private.discovery_owner(p_member) then raise exception 'Participant access required.'; end if;
 if jsonb_typeof(p_data)<>'object' or octet_length(p_data::text)>64000 then raise exception 'Profile is too large or invalid.'; end if;
 for k in select jsonb_object_keys(p_data) loop
 if k not in ('connection','service','joy','abilities','hope','occupation','skills','availability','contact','review_date','interests') then raise exception 'Unknown profile field.'; end if;
 end loop;
 foreach k in array array['connection','service','joy','abilities','hope','occupation','availability','contact','review_date','interests'] loop
 if p_data?k and (jsonb_typeof(p_data->k)<>'string' or length(p_data->>k)>5000) then raise exception 'Invalid profile answer.'; end if;
 end loop;
 if jsonb_typeof(p_data->'skills') is distinct from 'array' or jsonb_array_length(p_data->'skills')>100 then raise exception 'Choose up to 100 skills.'; end if;
 for item in select value from jsonb_array_elements(p_data->'skills') loop
 if jsonb_typeof(item)<>'object' or length(btrim(coalesce(item->>'name',''))) not between 1 and 120
 or jsonb_typeof(item->'name')<>'string'
 or item - array['name','experience','interest','notes'] <> '{}'::jsonb then raise exception 'Invalid skill.'; end if;
 foreach k in array array['experience','interest','notes'] loop
 if item?k and (jsonb_typeof(item->k)<>'string' or length(item->>k)>2000) then raise exception 'Invalid skill detail.'; end if;
 end loop;
 end loop;
 select * into r from public.discovery_profiles where membership_id=p_member for update;
 if p_revision is null or p_revision<0 or p_submit is null then raise exception 'Invalid revision.'; end if;
 if r.revision<>p_revision then raise exception 'This profile changed in another window. Refresh before saving.'; end if;
 update public.discovery_profiles set draft=p_data,submitted=case when p_submit then p_data else submitted end,
 revision=revision+1,updated_at=now() where membership_id=p_member returning * into r;
 return to_jsonb(r);
end;$$;

create function private.discovery_score(p_kind text,p_answers jsonb,p_questions jsonb)
returns jsonb language plpgsql immutable set search_path='' as $$
declare scores jsonb; domains jsonb:='{}'; code text; n integer; avgscore numeric;
begin
 select jsonb_object_agg(scale,case when answered=total then to_jsonb(case when p_kind='bigfive' and scale like 'N%' then 6-mean else mean end) else 'null'::jsonb end)
 into scores from (
 select q->>'scale' as scale,count(*) total,count(a) answered,avg(case when q->>'key'='-' then 6-a else a end) mean
 from jsonb_array_elements(p_questions) q
 left join lateral (select case when jsonb_typeof(p_answers->(q->>'id'))='number' then (p_answers->>(q->>'id'))::numeric end as a) v on true
 group by q->>'scale') s;
 if p_kind='bigfive' then
 foreach code in array array['O','C','E','A','N'] loop
 select count(*) filter(where value<>'null'::jsonb),avg(case when value<>'null'::jsonb then (value::text)::numeric end)
 into n,avgscore from jsonb_each(scores) where left(key,1)=code;
 domains:=domains||jsonb_build_object(code,case when n=6 then avgscore else null end);
 end loop;
 else domains:=scores;
 end if;
 return jsonb_build_object('scales',scores,'domains',domains);
end;$$;
revoke all on function private.discovery_score(text,jsonb,jsonb) from public,anon,authenticated;

create function public.discovery_save_assessment(p_member uuid,p_kind text,p_answers jsonb,p_revision integer,p_submit boolean default false,p_new_attempt boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare m public.discovery_memberships; a public.discovery_attempts; v private.discovery_versions; questions jsonb; k text; x jsonb;
begin
 if not private.discovery_owner(p_member) then raise exception 'Participant access required.'; end if;
 if p_revision is null or p_revision<0 or p_submit is null or p_new_attempt is null then raise exception 'Invalid revision.'; end if;
 if p_kind not in ('bigfive','motivations') or p_kind is null or jsonb_typeof(p_answers) is distinct from 'object' or octet_length(p_answers::text)>24000 then raise exception 'Invalid assessment.'; end if;
 select * into m from public.discovery_memberships where id=p_member for update;
 select * into v from private.discovery_versions order by created_at desc,version desc limit 1;
 questions:=v.questions->p_kind;
 if questions is null then raise exception 'Assessment content is unavailable.'; end if;
 for k,x in select * from jsonb_each(p_answers) loop
 if not exists(select 1 from jsonb_array_elements(questions) q where q->>'id'=k) then raise exception 'Unknown assessment question.'; end if;
 if x<>'null'::jsonb and (jsonb_typeof(x)<>'number' or x::text !~ '^[1-5]$') then raise exception 'Choose a whole-number answer from 1 to 5, or skip.'; end if;
 end loop;
 if p_submit and exists(select 1 from jsonb_array_elements(questions) q where not p_answers?(q->>'id')) then raise exception 'Answer or explicitly skip every question before submitting.'; end if;
 select * into a from public.discovery_attempts where membership_id=m.id and kind=p_kind and submitted_at is null for update;
 if a.id is null then
 if not p_new_attempt and exists(select 1 from public.discovery_attempts where membership_id=m.id and kind=p_kind and submitted_at is not null) then raise exception 'Start a new attempt to retake this assessment.'; end if;
 if p_revision<>0 then raise exception 'Refresh this assessment before saving.'; end if;
 insert into public.discovery_attempts(membership_id,church_id,kind,version) values(m.id,m.church_id,p_kind,v.version) returning * into a;
 end if;
 if a.version<>v.version or a.revision<>p_revision then raise exception 'This assessment changed. Refresh before saving.'; end if;
 update public.discovery_attempts set answers=p_answers,revision=revision+1,updated_at=now(),
 submitted_at=case when p_submit then now() end,
 scores=case when p_submit then private.discovery_score(p_kind,p_answers,questions) end
 where id=a.id returning * into a;
 return to_jsonb(a);
end;$$;

create function private.discovery_staff(p_church uuid,p_edit boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select private.has_church_role(p_church,case when p_edit then array['admin','editor'] else array['admin','editor','viewer'] end);
$$;
revoke all on function private.discovery_staff(uuid,boolean) from public,anon;
grant execute on function private.discovery_staff(uuid,boolean) to authenticated;

create function public.discovery_link_person(p_member uuid,p_person uuid default null,p_create boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare m public.discovery_memberships; pid uuid;
begin
 select * into m from public.discovery_memberships where id=p_member for update;
 if m.id is null or not private.discovery_staff(m.church_id,true) then raise exception 'Church editor access required.'; end if;
 if m.person_id is not null then raise exception 'This participant is already linked. Contact an administrator to resolve a duplicate.'; end if;
 if p_create then
 if p_person is not null then raise exception 'Choose an existing person or create one, not both.'; end if;
 insert into public.people(church_id,first_name,last_name,email,is_public)
 select m.church_id,m.first_name,m.last_name,u.email,false from auth.users u where u.id=m.user_id returning id into pid;
 else
 select id into pid from public.people where id=p_person and church_id=m.church_id;
 if pid is null then raise exception 'Choose a person from this church.'; end if;
 end if;
 update public.discovery_memberships set person_id=pid where id=m.id;
end;$$;

create function public.discovery_observe(p_member uuid,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare c uuid;
begin
 select church_id into c from public.discovery_memberships where id=p_member;
 if not coalesce(private.discovery_staff(c,true),false) then raise exception 'Church editor access required.'; end if;
 insert into public.discovery_observations(membership_id,church_id,author_id,note) values(p_member,c,auth.uid(),btrim(p_note));
end;$$;

create function public.discovery_staff_search(p_filters jsonb default '{}',p_offset integer default 0,p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c uuid:=private.current_church_id(); result jsonb; total bigint;
begin
 if not private.discovery_staff(c) then raise exception 'Placement team access required.'; end if;
 if jsonb_typeof(p_filters) is distinct from 'object' or octet_length(p_filters::text)>8000 or p_offset is null or p_limit is null or p_offset<0 or p_offset>100000 or p_limit not between 1 and 50 then raise exception 'Invalid search.'; end if;
 with entries as (
 select m.id,m.church_id,m.person_id,m.disabled,
 coalesce(p.first_name,m.first_name) first_name,coalesce(p.last_name,m.last_name) last_name,
 u.email,pr.submitted as profile,
 (select jsonb_build_object('submitted_at',a.submitted_at,'version',a.version,'domains',(a.scores->'domains')-'N')
 from public.discovery_attempts a where a.membership_id=m.id and a.kind='bigfive' and a.submitted_at is not null order by a.submitted_at desc,a.id desc limit 1) bigfive,
 (select jsonb_build_object('submitted_at',a.submitted_at,'version',a.version,'domains',a.scores->'domains')
 from public.discovery_attempts a where a.membership_id=m.id and a.kind='motivations' and a.submitted_at is not null order by a.submitted_at desc,a.id desc limit 1) motivations,
 coalesce((select jsonb_agg(jsonb_build_object('id',o.id,'note',o.note,'created_at',o.created_at,'author',coalesce(pf.display_name,'Former leader')) order by o.created_at desc)
 from public.discovery_observations o left join public.profiles pf on pf.user_id=o.author_id where o.membership_id=m.id),'[]'::jsonb) observations
 from public.discovery_memberships m join auth.users u on u.id=m.user_id
 left join public.people p on p.id=m.person_id and p.church_id=m.church_id
 left join public.discovery_profiles pr on pr.membership_id=m.id where m.church_id=c
 ), filtered as (
 select * from entries e where
 (coalesce(p_filters->>'person_id','')='' or e.person_id::text=p_filters->>'person_id') and
 (coalesce(p_filters->>'member_id','')='' or e.id::text=p_filters->>'member_id') and
 (coalesce(p_filters->>'pending','')<>'true' or e.person_id is null) and
 (coalesce(p_filters->>'q','')='' or strpos(lower(concat_ws(' ',first_name,last_name,email,profile::text)),lower(p_filters->>'q'))>0) and
 (coalesce(p_filters->>'skill','')='' or exists(select 1 from jsonb_array_elements(coalesce(profile->'skills','[]')) skill where strpos(lower(skill->>'name'),lower(p_filters->>'skill'))>0)) and
 (coalesce(p_filters->>'availability','')='' or profile->>'availability'=p_filters->>'availability') and
 (coalesce(p_filters->>'contact','')='' or profile->>'contact'=p_filters->>'contact') and
 (coalesce(p_filters->>'assessment','')='' or (p_filters->>'assessment'='bigfive' and bigfive is not null) or (p_filters->>'assessment'='motivations' and motivations is not null)) and
 (coalesce(p_filters->>'motivation','')='' or exists(select 1 from jsonb_each(motivations->'domains') v
 where v.key=p_filters->>'motivation' and v.value<>'null'::jsonb and (v.value::text)::numeric=(select max((w.value::text)::numeric) from jsonb_each(motivations->'domains') w where w.value<>'null'::jsonb))) and
 (coalesce(p_filters->>'trait','')='' or (p_filters->>'trait' in ('O','C','E','A') and
 case p_filters->>'range' when 'lower' then (bigfive->'domains'->>(p_filters->>'trait'))::numeric<2.5
 when 'higher' then (bigfive->'domains'->>(p_filters->>'trait'))::numeric>3.5
 else (bigfive->'domains'->>(p_filters->>'trait'))::numeric between 2.5 and 3.5 end))
 ), paged as (select * from filtered order by last_name,first_name,id offset p_offset limit p_limit)
 select jsonb_build_object('total',(select count(*) from filtered),'items',coalesce((select jsonb_agg(to_jsonb(paged)) from paged),'[]'::jsonb)) into result;
 return result;
end;$$;

-- No SECURITY DEFINER endpoint inherits PostgreSQL's default PUBLIC EXECUTE.
do $$
declare signature regprocedure;
begin
 for signature in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname like 'discovery_%' loop
 execute format('revoke all on function %s from public,anon,authenticated',signature);
 execute format('grant execute on function %s to authenticated',signature);
 end loop;
end;$$;
grant execute on function public.discovery_public_church(text) to anon;

create function public.discovery_my_churches() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'slug',c.slug) order by c.name),'[]'::jsonb)
 from public.churches c where private.discovery_staff(c.id) or exists(select 1 from public.discovery_memberships m where m.church_id=c.id and private.discovery_owner(m.id));
$$;
revoke all on function public.discovery_my_churches() from public,anon;
grant execute on function public.discovery_my_churches() to authenticated;
create function public.discovery_member_access(p_member uuid,p_disabled boolean)
returns void language plpgsql security definer set search_path='' as $$
declare c uuid;
begin
 select church_id into c from public.discovery_memberships where id=p_member for update;
 if not private.has_church_role(c,array['admin']) then raise exception 'Administrator access required.'; end if;
 if p_disabled is null then raise exception 'Choose an access state.'; end if;
 update public.discovery_memberships set disabled=p_disabled where id=p_member;
end;$$;
revoke all on function public.discovery_member_access(uuid,boolean) from public,anon;
grant execute on function public.discovery_member_access(uuid,boolean) to authenticated;

insert into private.discovery_versions(version,questions) values ('2026-10-26.1', $questions${"bigfive":[{"id":"N1-1","scale":"N1","text":"Worry about things.","key":"+"},{"id":"N1-2","scale":"N1","text":"Fear for the worst.","key":"+"},{"id":"N1-3","scale":"N1","text":"Am afraid of many things.","key":"+"},{"id":"N1-4","scale":"N1","text":"Get stressed out easily.","key":"+"},{"id":"N2-1","scale":"N2","text":"Get angry easily.","key":"+"},{"id":"N2-2","scale":"N2","text":"Get irritated easily.","key":"+"},{"id":"N2-3","scale":"N2","text":"Lose my temper.","key":"+"},{"id":"N2-4","scale":"N2","text":"Am not easily annoyed.","key":"-"},{"id":"N3-1","scale":"N3","text":"Often feel blue.","key":"+"},{"id":"N3-2","scale":"N3","text":"Dislike myself.","key":"+"},{"id":"N3-3","scale":"N3","text":"Am often down in the dumps.","key":"+"},{"id":"N3-4","scale":"N3","text":"Feel comfortable with myself.","key":"-"},{"id":"N4-1","scale":"N4","text":"Find it difficult to approach others.","key":"+"},{"id":"N4-2","scale":"N4","text":"Am afraid to draw attention to myself.","key":"+"},{"id":"N4-3","scale":"N4","text":"Only feel comfortable with friends.","key":"+"},{"id":"N4-4","scale":"N4","text":"Am not bothered by difficult social situations.","key":"-"},{"id":"N5-1","scale":"N5","text":"Go on binges.","key":"+"},{"id":"N5-2","scale":"N5","text":"Rarely overindulge.","key":"-"},{"id":"N5-3","scale":"N5","text":"Easily resist temptations.","key":"-"},{"id":"N5-4","scale":"N5","text":"Am able to control my cravings.","key":"-"},{"id":"N6-1","scale":"N6","text":"Panic easily.","key":"+"},{"id":"N6-2","scale":"N6","text":"Become overwhelmed by events.","key":"+"},{"id":"N6-3","scale":"N6","text":"Feel that I'm unable to deal with things.","key":"+"},{"id":"N6-4","scale":"N6","text":"Remain calm under pressure.","key":"-"},{"id":"E1-1","scale":"E1","text":"Make friends easily.","key":"+"},{"id":"E1-2","scale":"E1","text":"Feel comfortable around people.","key":"+"},{"id":"E1-3","scale":"E1","text":"Avoid contacts with others.","key":"-"},{"id":"E1-4","scale":"E1","text":"Keep others at a distance.","key":"-"},{"id":"E2-1","scale":"E2","text":"Love large parties.","key":"+"},{"id":"E2-2","scale":"E2","text":"Talk to a lot of different people at parties.","key":"+"},{"id":"E2-3","scale":"E2","text":"Prefer to be alone.","key":"-"},{"id":"E2-4","scale":"E2","text":"Avoid crowds.","key":"-"},{"id":"E3-1","scale":"E3","text":"Take charge.","key":"+"},{"id":"E3-2","scale":"E3","text":"Try to lead others.","key":"+"},{"id":"E3-3","scale":"E3","text":"Take control of things.","key":"+"},{"id":"E3-4","scale":"E3","text":"Wait for others to lead the way.","key":"-"},{"id":"E4-1","scale":"E4","text":"Am always busy.","key":"+"},{"id":"E4-2","scale":"E4","text":"Am always on the go.","key":"+"},{"id":"E4-3","scale":"E4","text":"Do a lot in my spare time.","key":"+"},{"id":"E4-4","scale":"E4","text":"Like to take it easy.","key":"-"},{"id":"E5-1","scale":"E5","text":"Love excitement.","key":"+"},{"id":"E5-2","scale":"E5","text":"Seek adventure.","key":"+"},{"id":"E5-3","scale":"E5","text":"Enjoy being reckless.","key":"+"},{"id":"E5-4","scale":"E5","text":"Act wild and crazy.","key":"+"},{"id":"E6-1","scale":"E6","text":"Radiate joy.","key":"+"},{"id":"E6-2","scale":"E6","text":"Have a lot of fun.","key":"+"},{"id":"E6-3","scale":"E6","text":"Love life.","key":"+"},{"id":"E6-4","scale":"E6","text":"Look at the bright side of life.","key":"+"},{"id":"O1-1","scale":"O1","text":"Have a vivid imagination.","key":"+"},{"id":"O1-2","scale":"O1","text":"Enjoy wild flights of fantasy.","key":"+"},{"id":"O1-3","scale":"O1","text":"Love to daydream.","key":"+"},{"id":"O1-4","scale":"O1","text":"Like to get lost in thought.","key":"+"},{"id":"O2-1","scale":"O2","text":"Believe in the importance of art.","key":"+"},{"id":"O2-2","scale":"O2","text":"See beauty in things that others might not notice.","key":"+"},{"id":"O2-3","scale":"O2","text":"Do not like poetry.","key":"-"},{"id":"O2-4","scale":"O2","text":"Do not enjoy going to art museums.","key":"-"},{"id":"O3-1","scale":"O3","text":"Experience my emotions intensely.","key":"+"},{"id":"O3-2","scale":"O3","text":"Feel others' emotions.","key":"+"},{"id":"O3-3","scale":"O3","text":"Rarely notice my emotional reactions.","key":"-"},{"id":"O3-4","scale":"O3","text":"Don't understand people who get emotional.","key":"-"},{"id":"O4-1","scale":"O4","text":"Prefer variety to routine.","key":"+"},{"id":"O4-2","scale":"O4","text":"Prefer to stick with things that I know.","key":"-"},{"id":"O4-3","scale":"O4","text":"Dislike changes.","key":"-"},{"id":"O4-4","scale":"O4","text":"Am attached to conventional ways.","key":"-"},{"id":"O5-1","scale":"O5","text":"Love to read challenging material.","key":"+"},{"id":"O5-2","scale":"O5","text":"Avoid philosophical discussions.","key":"-"},{"id":"O5-3","scale":"O5","text":"Prefer practical examples to abstract explanations.","key":"-"},{"id":"O5-4","scale":"O5","text":"Am not interested in theoretical discussions.","key":"-"},{"id":"O6-1","scale":"O6","text":"Enjoy considering viewpoints that challenge my assumptions.","key":"+"},{"id":"O6-2","scale":"O6","text":"Am willing to reconsider long-held opinions when I encounter good reasons.","key":"+"},{"id":"O6-3","scale":"O6","text":"Prefer established ways of thinking over unfamiliar viewpoints.","key":"-"},{"id":"O6-4","scale":"O6","text":"Prefer established approaches when people suggest changing longstanding practices.","key":"-"},{"id":"A1-1","scale":"A1","text":"Trust others.","key":"+"},{"id":"A1-2","scale":"A1","text":"Believe that others have good intentions.","key":"+"},{"id":"A1-3","scale":"A1","text":"Trust what people say.","key":"+"},{"id":"A1-4","scale":"A1","text":"Distrust people.","key":"-"},{"id":"A2-1","scale":"A2","text":"Use others for my own ends.","key":"-"},{"id":"A2-2","scale":"A2","text":"Cheat to get ahead.","key":"-"},{"id":"A2-3","scale":"A2","text":"Take advantage of others.","key":"-"},{"id":"A2-4","scale":"A2","text":"Obstruct others' plans.","key":"-"},{"id":"A3-1","scale":"A3","text":"Am concerned about others.","key":"+"},{"id":"A3-2","scale":"A3","text":"Love to help others.","key":"+"},{"id":"A3-3","scale":"A3","text":"Am indifferent to the feelings of others.","key":"-"},{"id":"A3-4","scale":"A3","text":"Take no time for others.","key":"-"},{"id":"A4-1","scale":"A4","text":"Love a good fight.","key":"-"},{"id":"A4-2","scale":"A4","text":"Yell at people.","key":"-"},{"id":"A4-3","scale":"A4","text":"Insult people.","key":"-"},{"id":"A4-4","scale":"A4","text":"Get back at others.","key":"-"},{"id":"A5-1","scale":"A5","text":"Believe that I am better than others.","key":"-"},{"id":"A5-2","scale":"A5","text":"Think highly of myself.","key":"-"},{"id":"A5-3","scale":"A5","text":"Have a high opinion of myself.","key":"-"},{"id":"A5-4","scale":"A5","text":"Boast about my virtues.","key":"-"},{"id":"A6-1","scale":"A6","text":"Sympathize with the homeless.","key":"+"},{"id":"A6-2","scale":"A6","text":"Feel sympathy for those who are worse off than myself.","key":"+"},{"id":"A6-3","scale":"A6","text":"Am not interested in other people's problems.","key":"-"},{"id":"A6-4","scale":"A6","text":"Try not to think about the needy.","key":"-"},{"id":"C1-1","scale":"C1","text":"Complete tasks successfully.","key":"+"},{"id":"C1-2","scale":"C1","text":"Excel in what I do.","key":"+"},{"id":"C1-3","scale":"C1","text":"Handle tasks smoothly.","key":"+"},{"id":"C1-4","scale":"C1","text":"Know how to get things done.","key":"+"},{"id":"C2-1","scale":"C2","text":"Like to tidy up.","key":"+"},{"id":"C2-2","scale":"C2","text":"Often forget to put things back in their proper place.","key":"-"},{"id":"C2-3","scale":"C2","text":"Leave a mess in my room.","key":"-"},{"id":"C2-4","scale":"C2","text":"Leave my belongings around.","key":"-"},{"id":"C3-1","scale":"C3","text":"Keep my promises.","key":"+"},{"id":"C3-2","scale":"C3","text":"Tell the truth.","key":"+"},{"id":"C3-3","scale":"C3","text":"Break rules.","key":"-"},{"id":"C3-4","scale":"C3","text":"Break my promises.","key":"-"},{"id":"C4-1","scale":"C4","text":"Do more than what's expected of me.","key":"+"},{"id":"C4-2","scale":"C4","text":"Work hard.","key":"+"},{"id":"C4-3","scale":"C4","text":"Put little time and effort into my work.","key":"-"},{"id":"C4-4","scale":"C4","text":"Do just enough work to get by.","key":"-"},{"id":"C5-1","scale":"C5","text":"Am always prepared.","key":"+"},{"id":"C5-2","scale":"C5","text":"Carry out my plans.","key":"+"},{"id":"C5-3","scale":"C5","text":"Waste my time.","key":"-"},{"id":"C5-4","scale":"C5","text":"Have difficulty starting tasks.","key":"-"},{"id":"C6-1","scale":"C6","text":"Jump into things without thinking.","key":"-"},{"id":"C6-2","scale":"C6","text":"Make rash decisions.","key":"-"},{"id":"C6-3","scale":"C6","text":"Rush into things.","key":"-"},{"id":"C6-4","scale":"C6","text":"Act without thinking.","key":"-"}],"motivations":[{"id":"A-1","scale":"A","text":"I am drawn to begin a ministry where an important need is not yet being met.","key":"+"},{"id":"A-2","scale":"A","text":"I enjoy helping a new ministry move from an idea to its first practical steps.","key":"+"},{"id":"A-3","scale":"A","text":"I look for ways the church could serve people it is not currently reaching.","key":"+"},{"id":"A-4","scale":"A","text":"I enjoy connecting people and resources around a new ministry opportunity.","key":"+"},{"id":"A-5","scale":"A","text":"I want to help others develop the confidence to begin new expressions of service.","key":"+"},{"id":"A-6","scale":"A","text":"When a ministry works well, I am interested in helping it take root in another setting.","key":"+"},{"id":"P-1","scale":"P","text":"I am drawn to help a ministry examine whether its practices reflect the teaching of Scripture.","key":"+"},{"id":"P-2","scale":"P","text":"I want to help a group address gaps between its stated values and its actions.","key":"+"},{"id":"P-3","scale":"P","text":"I am motivated to raise concerns when people are overlooked or treated unfairly.","key":"+"},{"id":"P-4","scale":"P","text":"I enjoy helping others reflect carefully on what faithfulness to God requires in a situation.","key":"+"},{"id":"P-5","scale":"P","text":"I want to help a ministry correct an unhealthy practice even when the conversation is difficult.","key":"+"},{"id":"P-6","scale":"P","text":"I am drawn to help a church respond to needed correction with humility and practical change.","key":"+"},{"id":"E-1","scale":"E","text":"I am drawn to build relationships with people who are exploring or unfamiliar with Christian faith.","key":"+"},{"id":"E-2","scale":"E","text":"I enjoy helping someone understand the good news about Jesus in language that makes sense to them.","key":"+"},{"id":"E-3","scale":"E","text":"I look for natural opportunities to invite someone to explore faith or church community.","key":"+"},{"id":"E-4","scale":"E","text":"I want to help the church listen to questions asked by people outside its usual circles.","key":"+"},{"id":"E-5","scale":"E","text":"I am motivated to follow up with someone who has shown interest in learning about Jesus.","key":"+"},{"id":"E-6","scale":"E","text":"I enjoy helping other Christians become more comfortable sharing their faith respectfully.","key":"+"},{"id":"S-1","scale":"S","text":"I am drawn to maintain contact with people who need ongoing encouragement.","key":"+"},{"id":"S-2","scale":"S","text":"I enjoy helping someone feel included in the church community.","key":"+"},{"id":"S-3","scale":"S","text":"I am motivated to listen patiently when someone is going through a difficult season.","key":"+"},{"id":"S-4","scale":"S","text":"I want to help people build relationships that support their spiritual growth.","key":"+"},{"id":"S-5","scale":"S","text":"I notice when someone has become disconnected and want to help them reconnect.","key":"+"},{"id":"S-6","scale":"S","text":"I enjoy walking alongside someone over time rather than helping only once.","key":"+"},{"id":"T-1","scale":"T","text":"I am drawn to study a Bible passage carefully so I can help others understand it.","key":"+"},{"id":"T-2","scale":"T","text":"I enjoy explaining a difficult idea in a way someone can grasp.","key":"+"},{"id":"T-3","scale":"T","text":"I want to help people connect biblical teaching with everyday decisions.","key":"+"},{"id":"T-4","scale":"T","text":"I am motivated to check the accuracy and context of something before teaching it.","key":"+"},{"id":"T-5","scale":"T","text":"I enjoy adjusting an explanation when someone has not yet understood it.","key":"+"},{"id":"T-6","scale":"T","text":"I want to help others develop their own ability to study and understand Scripture.","key":"+"}]}$questions$::jsonb);

create function public.discovery_candidates(p_member uuid,p_query text default '')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m public.discovery_memberships; mail text; result jsonb;
begin
 select * into m from public.discovery_memberships where id=p_member;
 if m.id is null or not private.discovery_staff(m.church_id) then raise exception 'Placement team access required.'; end if;
 if length(p_query)>240 then raise exception 'Search is too long.'; end if;
 select lower(email) into mail from auth.users where id=m.user_id;
 select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into result from (
 select p.id,p.first_name,p.last_name,p.email,
 case when lower(p.email)=mail and lower(p.first_name)=lower(m.first_name) and lower(p.last_name)=lower(m.last_name)
 then 'Same email and full name'
 when lower(p.email)=mail then 'Same email; check whether it is shared'
 when lower(p.first_name)=lower(m.first_name) and lower(p.last_name)=lower(m.last_name)
 then 'Same full name; verify identity'
 else 'Name or email search match' end as reason
 from public.people p where p.church_id=m.church_id
 and not exists(select 1 from public.discovery_memberships other where other.church_id=m.church_id and other.person_id=p.id and other.id<>m.id)
 and (case when btrim(p_query)='' then lower(p.email)=mail or (lower(p.first_name)=lower(m.first_name) and lower(p.last_name)=lower(m.last_name))
 else strpos(lower(concat_ws(' ',p.first_name,p.last_name,p.email)),lower(btrim(p_query)))>0 end)
 order by (lower(p.email)=mail) desc nulls last,p.last_name,p.first_name,p.id limit 20
 ) x;
 return result;
end;$$;
revoke all on function public.discovery_candidates(uuid,text) from public,anon;
grant execute on function public.discovery_candidates(uuid,text) to authenticated;

create function public.discovery_enroll_leader(p_first_name text,p_last_name text,p_consent boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c uuid:=private.current_church_id(); t text;
begin
 if not private.discovery_staff(c) then raise exception 'Use the registration link shared by your church.'; end if;
 insert into private.discovery_settings(church_id) values(c) on conflict do nothing;
 select token into t from private.discovery_settings where church_id=c and enabled;
 if t is null then raise exception 'Registration is paused. Contact your church administrator.'; end if;
 return public.discovery_enroll(t,p_first_name,p_last_name,p_consent);
end;$$;
revoke all on function public.discovery_enroll_leader(text,text,boolean) from public,anon;
grant execute on function public.discovery_enroll_leader(text,text,boolean) to authenticated;
