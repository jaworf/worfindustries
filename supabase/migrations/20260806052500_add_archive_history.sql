alter table public.assignments
add column if not exists archived_at timestamptz;

alter table public.roles
add column if not exists archived_at timestamptz;

update public.assignments
set archived_at = coalesce(archived_at, updated_at)
where status = 'completed' and archived_at is null;

update public.roles
set archived_at = coalesce(archived_at, updated_at)
where not is_active and archived_at is null;

create or replace function public.sync_assignment_archive_timestamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'completed' then
    new.archived_at := coalesce(new.archived_at, now());
  else
    new.archived_at := null;
  end if;
  return new;
end;
$$;

revoke all on function public.sync_assignment_archive_timestamp() from public;

drop trigger if exists assignments_sync_archive_timestamp on public.assignments;
create trigger assignments_sync_archive_timestamp
before insert or update of status, archived_at on public.assignments
for each row execute function public.sync_assignment_archive_timestamp();

create or replace function public.sync_ministry_archive_timestamp()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not new.is_active then
    new.archived_at := coalesce(new.archived_at, now());
  else
    new.archived_at := null;
  end if;
  return new;
end;
$$;

revoke all on function public.sync_ministry_archive_timestamp() from public;

drop trigger if exists roles_sync_archive_timestamp on public.roles;
create trigger roles_sync_archive_timestamp
before insert or update of is_active, archived_at on public.roles
for each row execute function public.sync_ministry_archive_timestamp();

create index if not exists assignments_person_status_idx
on public.assignments (person_id, status, archived_at desc);

create index if not exists roles_active_name_idx
on public.roles (is_active, lower(btrim(name)));

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
  coalesce(sr.requires_vote, false) as position_requires_vote,
  a.archived_at,
  r.is_active as ministry_is_active,
  r.archived_at as ministry_archived_at
from public.assignments a
join public.people p on p.id = a.person_id
join public.roles r on r.id = a.role_id
left join public.sub_roles sr on sr.id = a.sub_role_id
left join public.terms t on t.id = a.term_id;

grant select on public.assignment_details to authenticated, service_role;

notify pgrst, 'reload schema';
