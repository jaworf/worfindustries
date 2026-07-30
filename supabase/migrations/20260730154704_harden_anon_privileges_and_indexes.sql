revoke all privileges on all tables in schema public from anon;
revoke all privileges on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon;

grant usage on schema public to anon;

grant select (
  id, first_name, preferred_name, last_name, is_public, is_active
) on public.people to anon;

grant select (
  id, name, display_order, is_public, is_active
) on public.roles to anon;

grant select (
  id, role_id, name, leadership_rank
) on public.sub_roles to anon;

grant select (
  id, name, start_date, end_date, term_type
) on public.terms to anon;

grant select (
  id, person_id, role_id, sub_role_id, term_id, vote_date, is_public, status
) on public.assignments to anon;

grant select on public.public_directory_entries to anon;

alter default privileges for role postgres in schema public
  revoke all on tables from anon;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon;

create index if not exists import_runs_started_by_idx
  on public.import_runs (started_by);
create index if not exists import_rows_person_idx
  on public.import_rows (person_id);
create index if not exists import_rows_assignment_idx
  on public.import_rows (assignment_id);
create index if not exists import_conflicts_row_idx
  on public.import_conflicts (import_row_id);
create index if not exists import_conflicts_resolved_by_idx
  on public.import_conflicts (resolved_by);
