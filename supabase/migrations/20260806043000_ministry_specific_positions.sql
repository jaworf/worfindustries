alter table public.sub_roles
add column if not exists requires_vote boolean not null default false;

comment on column public.sub_roles.requires_vote is
  'Whether this position, independently of its ministry, requires a church vote.';

-- Earlier CSV imports created reusable global positions. Preserve every used
-- label and rank while giving each ministry its own independently configurable
-- position record.
insert into public.sub_roles (
  role_id,
  name,
  leadership_rank,
  is_active,
  requires_vote
)
select distinct
  a.role_id,
  sr.name,
  sr.leadership_rank,
  sr.is_active,
  false
from public.assignments a
join public.sub_roles sr on sr.id = a.sub_role_id
where sr.role_id is distinct from a.role_id
on conflict do nothing;

update public.assignments a
set sub_role_id = target.id
from public.sub_roles source,
     public.sub_roles target
where source.id = a.sub_role_id
  and source.role_id is distinct from a.role_id
  and target.role_id = a.role_id
  and lower(btrim(target.name)) = lower(btrim(source.name));

-- Keep future legacy CSV imports safe: a global or mismatched position is
-- automatically copied into the selected ministry before the assignment is
-- written. Direct app-created positions are already ministry-specific.
create or replace function public.normalize_assignment_position()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source public.sub_roles%rowtype;
  v_target_id uuid;
begin
  if new.sub_role_id is null then
    return new;
  end if;

  select *
  into v_source
  from public.sub_roles
  where id = new.sub_role_id;

  if not found then
    raise exception 'The selected position does not exist.';
  end if;

  if v_source.role_id = new.role_id then
    return new;
  end if;

  insert into public.sub_roles (
    role_id,
    name,
    leadership_rank,
    is_active,
    requires_vote
  )
  values (
    new.role_id,
    v_source.name,
    v_source.leadership_rank,
    v_source.is_active,
    v_source.requires_vote
  )
  on conflict do nothing;

  select id
  into v_target_id
  from public.sub_roles
  where role_id = new.role_id
    and lower(btrim(name)) = lower(btrim(v_source.name));

  if v_target_id is null then
    raise exception 'The position could not be linked to the selected ministry.';
  end if;

  new.sub_role_id := v_target_id;
  return new;
end;
$$;

revoke all on function public.normalize_assignment_position() from public;
revoke all on function public.normalize_assignment_position() from anon, authenticated;

drop trigger if exists assignments_normalize_position on public.assignments;
create trigger assignments_normalize_position
before insert or update of role_id, sub_role_id on public.assignments
for each row execute function public.normalize_assignment_position();

create or replace view public.assignment_details
with (security_invoker = true, security_barrier = true)
as
select
  a.id,
  a.person_id,
  p.first_name,
  p.preferred_name,
  p.last_name,
  concat_ws(' ', coalesce(nullif(p.preferred_name, ''), p.first_name), p.last_name)
    as person_name,
  p.email,
  p.mobile_phone,
  p.home_phone,
  a.role_id,
  r.name as role_name,
  a.sub_role_id,
  sr.name as sub_role_name,
  coalesce(sr.leadership_rank, 100) as leadership_rank,
  a.term_id,
  t.name as term_name,
  t.start_date,
  t.end_date,
  t.term_type,
  a.vote_date,
  (r.requires_vote or coalesce(sr.requires_vote, false)) as requires_vote,
  (
    (r.requires_vote or coalesce(sr.requires_vote, false))
    and a.vote_date is null
  ) as vote_missing,
  a.status,
  a.is_public,
  a.notes,
  a.created_at,
  a.updated_at,
  a.note_is_public,
  r.requires_vote as ministry_requires_vote,
  coalesce(sr.requires_vote, false) as position_requires_vote
from public.assignments a
join public.people p on p.id = a.person_id
join public.roles r on r.id = a.role_id
left join public.sub_roles sr on sr.id = a.sub_role_id
left join public.terms t on t.id = a.term_id;

grant select on public.assignment_details to authenticated, service_role;

notify pgrst, 'reload schema';
