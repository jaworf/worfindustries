-- Cover composite tenant foreign keys used by joins and cascading checks.

create index planning_center_connections_configured_by_idx
  on private.planning_center_connections (configured_by);
create index person_external_ids_person_church_idx
  on public.person_external_ids (person_id, church_id);
create index sub_roles_role_church_idx
  on public.sub_roles (role_id, church_id);
create index assignments_person_church_idx
  on public.assignments (person_id, church_id);
create index assignments_role_church_idx
  on public.assignments (role_id, church_id);
create index assignments_sub_role_church_idx
  on public.assignments (sub_role_id, church_id);
create index assignments_term_church_idx
  on public.assignments (term_id, church_id);
create index assignment_external_ids_assignment_church_idx
  on public.assignment_external_ids (assignment_id, church_id);
create index import_rows_run_church_idx
  on public.import_rows (import_run_id, church_id);
create index import_rows_person_church_idx
  on public.import_rows (person_id, church_id);
create index import_rows_assignment_church_idx
  on public.import_rows (assignment_id, church_id);
create index import_rows_church_idx
  on public.import_rows (church_id);
create index import_conflicts_run_church_idx
  on public.import_conflicts (import_run_id, church_id);
create index import_conflicts_row_church_idx
  on public.import_conflicts (import_row_id, church_id);
create index import_conflicts_church_idx
  on public.import_conflicts (church_id);

