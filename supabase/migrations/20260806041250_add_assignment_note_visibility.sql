alter table public.assignments
add column if not exists note_is_public boolean not null default false,
add column if not exists public_note text generated always as (
  case
    when note_is_public then nullif(btrim(notes), '')
    else null
  end
) stored;

comment on column public.assignments.note_is_public is
  'When true, the assignment note may appear in staff-generated reports and the public directory.';
comment on column public.assignments.public_note is
  'Generated privacy boundary exposing note text only when note_is_public is true.';

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
  r.requires_vote,
  (r.requires_vote and a.vote_date is null) as vote_missing,
  a.status,
  a.is_public,
  a.notes,
  a.created_at,
  a.updated_at,
  a.note_is_public
from public.assignments a
join public.people p on p.id = a.person_id
join public.roles r on r.id = a.role_id
left join public.sub_roles sr on sr.id = a.sub_role_id
left join public.terms t on t.id = a.term_id;

create or replace view public.public_directory_entries
with (security_invoker = true, security_barrier = true)
as
select
  a.id,
  concat_ws(' ', coalesce(nullif(p.preferred_name, ''), p.first_name), p.last_name)
    as person_name,
  p.last_name,
  p.first_name,
  r.name as role_name,
  sr.name as sub_role_name,
  coalesce(sr.leadership_rank, 100) as leadership_rank,
  t.name as term_name,
  t.start_date,
  t.end_date,
  a.vote_date,
  a.public_note as note
from public.assignments a
join public.people p on p.id = a.person_id
join public.roles r on r.id = a.role_id
left join public.sub_roles sr on sr.id = a.sub_role_id
left join public.terms t on t.id = a.term_id
where
  a.is_public
  and a.status = 'active'
  and p.is_public
  and p.is_active
  and r.is_public
  and r.is_active
order by
  r.display_order,
  r.name,
  coalesce(sr.leadership_rank, 100),
  p.last_name,
  p.first_name;

grant select (public_note) on public.assignments to anon;
grant select on public.assignment_details to authenticated, service_role;
grant select on public.public_directory_entries to anon, authenticated, service_role;

notify pgrst, 'reload schema';
