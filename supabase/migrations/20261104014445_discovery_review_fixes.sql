-- Owner identity is server-controlled and separate from editable profiles.
create table public.church_owners (
 church_id uuid primary key references public.churches(id),
 user_id uuid not null unique references auth.users(id) on delete restrict,
 assigned_at timestamptz not null default now()
);
alter table public.church_owners enable row level security;
revoke all on public.church_owners from public,anon,authenticated;
grant select on public.church_owners to authenticated;
grant all on public.church_owners to service_role;
create policy church_owners_read on public.church_owners for select to authenticated using(private.has_church_role(church_id,array['admin']));
-- Approved founders take precedence. Legacy churches use their earliest active
-- administrator.
insert into public.church_owners(church_id,user_id)
select distinct on (p.church_id) p.church_id,p.user_id
from public.profiles p left join public.church_applications a on a.church_id=p.church_id and a.applicant_id=p.user_id and a.status='approved'
where p.church_id is not null and p.app_role='admin' and not p.access_disabled and not p.must_change_password
order by p.church_id,(a.id is not null) desc,p.created_at,p.user_id;

create function private.guard_church_owner() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.church_owners where user_id=old.user_id) and
 (tg_op='DELETE' or new.church_id is distinct from old.church_id or new.app_role<>'admin' or new.access_disabled or new.must_change_password) then
  raise exception 'Transfer church ownership before removing or changing the owner account.';
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end;$$;
revoke all on function private.guard_church_owner() from public,anon,authenticated;
create trigger guard_church_owner before update or delete on public.profiles for each row execute function private.guard_church_owner();

create function private.establish_church_owner() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.church_id is not null and new.app_role='admin' and not new.access_disabled and not new.must_change_password then
  insert into public.church_owners(church_id,user_id) values(new.church_id,new.user_id) on conflict(church_id) do nothing;
 end if;
 return new;
end;$$;
revoke all on function private.establish_church_owner() from public,anon,authenticated;
create trigger establish_church_owner after insert or update on public.profiles for each row execute function private.establish_church_owner();

create function private.transfer_church_ownership(p_church_id uuid,p_user_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare actor public.profiles; previous uuid;
begin
 select * into actor from public.profiles where user_id=auth.uid();
 if actor.user_id is null or actor.app_role<>'admin' or actor.access_disabled or actor.must_change_password then raise exception 'Administrator access required.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_church_id::text,0));
 select user_id into previous from public.church_owners where church_id=p_church_id for update;
 if previous is distinct from actor.user_id and not actor.is_platform_admin then raise exception 'Only the church owner or platform administrator may transfer ownership.'; end if;
 if not exists(select 1 from public.churches where id=p_church_id and is_active) then raise exception 'Church unavailable.'; end if;
 if not exists(select 1 from public.profiles where user_id=p_user_id and church_id=p_church_id and app_role='admin' and not access_disabled and not must_change_password) then raise exception 'Choose an active administrator in this church.'; end if;
 insert into public.church_owners(church_id,user_id) values(p_church_id,p_user_id) on conflict(church_id) do update set user_id=excluded.user_id,assigned_at=now();
 insert into public.app_access_audit(church_id,actor_id,user_id,before_access,after_access) values(p_church_id,actor.user_id,p_user_id,jsonb_build_object('owner_id',previous),jsonb_build_object('owner_id',p_user_id));
end;$$;
revoke all on function private.transfer_church_ownership(uuid,uuid) from public,anon;
grant execute on function private.transfer_church_ownership(uuid,uuid) to authenticated;
create function public.transfer_church_ownership(p_church_id uuid,p_user_id uuid) returns void language sql security invoker set search_path='' as $$select private.transfer_church_ownership(p_church_id,p_user_id)$$;
revoke all on function public.transfer_church_ownership(uuid,uuid) from public,anon;
grant execute on function public.transfer_church_ownership(uuid,uuid) to authenticated;

create or replace function private.discovery_staff(p_church uuid,p_edit boolean default false) returns boolean
language sql stable security definer set search_path='' as $$
 select private.has_church_role(p_church,array['admin','editor']);
$$;

create or replace function public.discovery_staff_search(p_filters jsonb default '{}',p_offset integer default 0,p_limit integer default 20)
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
 (coalesce(p_filters->>'q','')='' or strpos(lower(concat_ws(' ',first_name,last_name,email,(select string_agg(value #>> '{}',' ') from jsonb_path_query(profile,'$.** ? (@.type() == "string")') value))),lower(p_filters->>'q'))>0) and
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
create or replace function public.discovery_observe(p_member uuid,p_note text)
returns void language plpgsql security definer set search_path='' as $$
declare c uuid;
begin
 select church_id into c from public.discovery_memberships where id=p_member;
 if not coalesce(private.discovery_staff(c,true),false) then raise exception 'Church editor access required.'; end if;
 if p_note is null or length(btrim(p_note)) not between 1 and 4000 then raise exception 'Enter an observation between 1 and 4000 characters.'; end if;
 insert into public.discovery_observations(membership_id,church_id,author_id,note) values(p_member,c,auth.uid(),btrim(p_note));
end;$$;
create or replace function public.discovery_enroll(p_token text,p_first_name text,p_last_name text,p_consent boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c uuid; m public.discovery_memberships;
begin
 if auth.uid() is null or p_consent is distinct from true then raise exception 'Sign in and accept the sharing notice.'; end if;
 if p_first_name is null or p_last_name is null or length(btrim(p_first_name)) not between 1 and 100 or length(btrim(p_last_name)) not between 1 and 100 then raise exception 'Enter first and last names between 1 and 100 characters each.'; end if;
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
