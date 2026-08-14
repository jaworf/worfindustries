-- Ordination belongs to the person, not to a volunteer assignment. These flags
-- therefore remain true when an assignment or ministry is later archived.
alter table public.people
  add column if not exists is_ordained_deacon boolean not null default false,
  add column if not exists is_ordained_deaconess boolean not null default false,
  add column if not exists is_ordained_elder boolean not null default false;

comment on column public.people.is_ordained_deacon is
  'Permanent person-level record that the individual is an ordained deacon.';
comment on column public.people.is_ordained_deaconess is
  'Permanent person-level record that the individual is an ordained deaconess.';
comment on column public.people.is_ordained_elder is
  'Permanent person-level record that the individual is an ordained elder.';

-- Initialize the permanent flags from current, active ministry placements.
-- Future assignment archiving does not change these person-level fields.
update public.people p
set is_ordained_deacon = true
where exists (
  select 1
  from public.assignments a
  join public.roles r on r.id = a.role_id
  left join public.terms t on t.id = a.term_id
  where a.person_id = p.id
    and a.status = 'active'
    and r.is_active
    and lower(btrim(r.name)) = 'deacon'
    and (t.end_date is null or t.end_date >= current_date)
);

update public.people p
set is_ordained_deaconess = true
where exists (
  select 1
  from public.assignments a
  join public.roles r on r.id = a.role_id
  left join public.terms t on t.id = a.term_id
  where a.person_id = p.id
    and a.status = 'active'
    and r.is_active
    and lower(btrim(r.name)) = 'deaconess'
    and (t.end_date is null or t.end_date >= current_date)
);

update public.people p
set is_ordained_elder = true
where exists (
  select 1
  from public.assignments a
  join public.roles r on r.id = a.role_id
  left join public.terms t on t.id = a.term_id
  where a.person_id = p.id
    and a.status = 'active'
    and r.is_active
    and lower(btrim(r.name)) = 'elder'
    and (t.end_date is null or t.end_date >= current_date)
);

-- These two current volunteers have not yet been ordained.
update public.people
set is_ordained_deacon = false
where lower(btrim(first_name)) = 'yadelky'
  and lower(btrim(last_name)) = 'henry';

update public.people
set is_ordained_elder = false
where lower(btrim(first_name)) = 'victoria'
  and lower(btrim(last_name)) = 'lahti';

notify pgrst, 'reload schema';
