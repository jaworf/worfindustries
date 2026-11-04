-- A blank position represents team membership, which does not require a term or vote.
-- Preserve existing records, grants, tenant joins, and invoker security.
create or replace view public.assignment_details
with (security_invoker = true, security_barrier = true)
as
select
  a.church_id,
  c.name as church_name,
  c.slug as church_slug,
  a.id,
  a.person_id,
  p.first_name,
  p.preferred_name,
  p.last_name,
  concat_ws(' ', coalesce(nullif(p.preferred_name, ''), p.first_name), p.last_name) as person_name,
  p.email,
  p.mobile_phone,
  p.home_phone,
  a.role_id,
  r.name as role_name,
  a.sub_role_id,
  sr.name as sub_role_name,
  coalesce(sr.leadership_rank::integer, 100) as leadership_rank,
  a.term_id,
  t.name as term_name,
  t.start_date,
  t.end_date,
  t.term_type,
  a.vote_date,
  (a.sub_role_id is not null and (r.requires_vote or coalesce(sr.requires_vote, false))) as requires_vote,
  ((a.sub_role_id is not null and (r.requires_vote or coalesce(sr.requires_vote, false))) and a.vote_date is null) as vote_missing,
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
join public.churches c on c.id = a.church_id
join public.people p on p.id = a.person_id and p.church_id = a.church_id
join public.roles r on r.id = a.role_id and r.church_id = a.church_id
left join public.sub_roles sr on sr.id = a.sub_role_id and sr.church_id = a.church_id
left join public.terms t on t.id = a.term_id and t.church_id = a.church_id;
