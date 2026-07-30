create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated, service_role;

create table public.profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  app_role text not null default 'viewer'
    check (app_role in ('admin', 'editor', 'viewer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.people (
  id uuid primary key default extensions.gen_random_uuid(),
  first_name text not null check (btrim(first_name) <> ''),
  middle_name text,
  last_name text not null check (btrim(last_name) <> ''),
  preferred_name text,
  suffix text,
  email text,
  mobile_phone text,
  home_phone text,
  address_line_1 text,
  address_line_2 text,
  city text,
  state_region text,
  postal_code text,
  country_code text,
  notes text,
  is_active boolean not null default true,
  is_public boolean not null default true,
  source_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  normalized_name text generated always as (
    lower(
      regexp_replace(
        first_name || ' ' || last_name,
        '[^a-zA-Z0-9]+',
        '',
        'g'
      )
    )
  ) stored,
  normalized_email text generated always as (
    lower(regexp_replace(coalesce(email, ''), '[[:space:]]+', '', 'g'))
  ) stored,
  normalized_phone text generated always as (
    regexp_replace(
      coalesce(nullif(mobile_phone, ''), nullif(home_phone, ''), ''),
      '[^0-9]+',
      '',
      'g'
    )
  ) stored
);

create table public.person_external_ids (
  id uuid primary key default extensions.gen_random_uuid(),
  person_id uuid not null references public.people (id) on delete cascade,
  source_system text not null check (btrim(source_system) <> ''),
  external_id text not null check (btrim(external_id) <> ''),
  source_updated_at timestamptz,
  source_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_system, external_id)
);

create table public.roles (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null check (btrim(name) <> ''),
  description text,
  requires_vote boolean not null default false,
  is_active boolean not null default true,
  is_public boolean not null default true,
  display_order integer not null default 1000,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index roles_name_ci_unique
  on public.roles (lower(btrim(name)));

create table public.sub_roles (
  id uuid primary key default extensions.gen_random_uuid(),
  role_id uuid references public.roles (id) on delete cascade,
  name text not null check (btrim(name) <> ''),
  leadership_rank smallint not null default 100
    check (leadership_rank between 0 and 1000),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index sub_roles_name_ci_unique
  on public.sub_roles (
    coalesce(role_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(btrim(name))
  );

create table public.terms (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null check (btrim(name) <> ''),
  start_date date,
  end_date date,
  term_type text not null default 'custom'
    check (term_type in ('calendar', 'fiscal', 'seasonal', 'custom', 'ongoing')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (term_type = 'ongoing' and start_date is null and end_date is null)
    or
    (term_type <> 'ongoing' and start_date is not null and end_date is not null
      and start_date <= end_date)
  )
);

create unique index terms_name_ci_unique
  on public.terms (lower(btrim(name)));

create table public.assignments (
  id uuid primary key default extensions.gen_random_uuid(),
  person_id uuid not null references public.people (id) on delete restrict,
  role_id uuid not null references public.roles (id) on delete restrict,
  sub_role_id uuid references public.sub_roles (id) on delete set null,
  term_id uuid references public.terms (id) on delete restrict,
  vote_date date,
  notes text,
  status text not null default 'active'
    check (status in ('draft', 'active', 'completed', 'declined')),
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index assignments_natural_unique
  on public.assignments (
    person_id,
    role_id,
    coalesce(sub_role_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(term_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

create table public.assignment_external_ids (
  id uuid primary key default extensions.gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id) on delete cascade,
  source_system text not null check (btrim(source_system) <> ''),
  external_id text not null check (btrim(external_id) <> ''),
  source_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_system, external_id)
);

create table public.import_runs (
  id uuid primary key default extensions.gen_random_uuid(),
  source_type text not null
    check (source_type in ('members_csv', 'assignments_csv', 'planning_center', 'manual')),
  source_name text,
  status text not null default 'processing'
    check (status in ('processing', 'completed', 'completed_with_conflicts', 'failed')),
  inserted_count integer not null default 0,
  updated_count integer not null default 0,
  unchanged_count integer not null default 0,
  conflict_count integer not null default 0,
  error_count integer not null default 0,
  started_by uuid references auth.users (id) on delete set null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  error_message text,
  created_at timestamptz not null default now()
);

create table public.import_rows (
  id uuid primary key default extensions.gen_random_uuid(),
  import_run_id uuid references public.import_runs (id) on delete cascade,
  row_number integer,
  source_external_id text,
  person_id uuid references public.people (id) on delete set null,
  assignment_id uuid references public.assignments (id) on delete set null,
  outcome text not null
    check (outcome in ('inserted', 'updated', 'unchanged', 'conflict', 'error')),
  message text,
  raw_record jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.import_conflicts (
  id uuid primary key default extensions.gen_random_uuid(),
  import_run_id uuid references public.import_runs (id) on delete cascade,
  import_row_id uuid references public.import_rows (id) on delete cascade,
  candidate_person_ids uuid[] not null default '{}'::uuid[],
  conflict_type text not null
    check (conflict_type in ('ambiguous_person', 'field_mismatch', 'missing_person', 'invalid_term')),
  incoming_values jsonb not null default '{}'::jsonb,
  existing_values jsonb not null default '{}'::jsonb,
  resolution text
    check (resolution is null or resolution in ('use_existing', 'use_incoming', 'merge', 'create_new', 'ignored')),
  resolved_by uuid references auth.users (id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  table_name text not null,
  record_id uuid,
  operation text not null check (operation in ('INSERT', 'UPDATE', 'DELETE')),
  changed_by uuid,
  old_values jsonb,
  new_values jsonb,
  changed_at timestamptz not null default now()
);

create table public.webhook_deliveries (
  id uuid primary key default extensions.gen_random_uuid(),
  source_system text not null check (btrim(source_system) <> ''),
  delivery_id text not null check (btrim(delivery_id) <> ''),
  event_name text not null,
  status text not null default 'processing'
    check (status in ('processing', 'completed', 'ignored', 'failed')),
  payload jsonb not null default '{}'::jsonb,
  error_message text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique (source_system, delivery_id)
);

create index people_name_search_idx on public.people (normalized_name);
create index people_email_search_idx on public.people (normalized_email);
create index people_phone_search_idx on public.people (normalized_phone);
create index person_external_ids_person_idx on public.person_external_ids (person_id);
create index sub_roles_role_idx on public.sub_roles (role_id);
create index assignments_person_idx on public.assignments (person_id);
create index assignments_role_idx on public.assignments (role_id);
create index assignments_term_idx on public.assignments (term_id);
create index assignments_sub_role_idx on public.assignments (sub_role_id);
create index assignment_external_ids_assignment_idx
  on public.assignment_external_ids (assignment_id);
create index import_rows_run_idx on public.import_rows (import_run_id);
create index import_conflicts_run_idx on public.import_conflicts (import_run_id);
create index audit_log_record_idx on public.audit_log (table_name, record_id);
create index webhook_deliveries_received_idx
  on public.webhook_deliveries (received_at desc);

create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function private.set_updated_at() from public, anon, authenticated;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function private.set_updated_at();

create trigger people_set_updated_at
before update on public.people
for each row execute function private.set_updated_at();

create trigger person_external_ids_set_updated_at
before update on public.person_external_ids
for each row execute function private.set_updated_at();

create trigger roles_set_updated_at
before update on public.roles
for each row execute function private.set_updated_at();

create trigger sub_roles_set_updated_at
before update on public.sub_roles
for each row execute function private.set_updated_at();

create trigger terms_set_updated_at
before update on public.terms
for each row execute function private.set_updated_at();

create trigger assignments_set_updated_at
before update on public.assignments
for each row execute function private.set_updated_at();

create trigger assignment_external_ids_set_updated_at
before update on public.assignment_external_ids
for each row execute function private.set_updated_at();

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (user_id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1))
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function private.handle_new_user();

create or replace function private.has_ministry_role(allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and exists (
      select 1
      from public.profiles
      where user_id = (select auth.uid())
        and app_role = any (allowed_roles)
    );
$$;

revoke all on function private.has_ministry_role(text[]) from public, anon;
grant execute on function private.has_ministry_role(text[]) to authenticated, service_role;

create or replace function private.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record_id uuid;
begin
  if tg_op = 'DELETE' then
    v_record_id := old.id;
    insert into public.audit_log (
      table_name, record_id, operation, changed_by, old_values
    )
    values (
      tg_table_name, v_record_id, tg_op, (select auth.uid()), to_jsonb(old)
    );
    return old;
  end if;

  v_record_id := new.id;
  insert into public.audit_log (
    table_name, record_id, operation, changed_by, old_values, new_values
  )
  values (
    tg_table_name,
    v_record_id,
    tg_op,
    (select auth.uid()),
    case when tg_op = 'UPDATE' then to_jsonb(old) else null end,
    to_jsonb(new)
  );
  return new;
end;
$$;

revoke all on function private.write_audit_log() from public, anon, authenticated;

create trigger people_audit
after insert or update or delete on public.people
for each row execute function private.write_audit_log();

create trigger roles_audit
after insert or update or delete on public.roles
for each row execute function private.write_audit_log();

create trigger sub_roles_audit
after insert or update or delete on public.sub_roles
for each row execute function private.write_audit_log();

create trigger terms_audit
after insert or update or delete on public.terms
for each row execute function private.write_audit_log();

create trigger assignments_audit
after insert or update or delete on public.assignments
for each row execute function private.write_audit_log();

create or replace function public.leadership_rank(sub_role_name text)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select case lower(btrim(coalesce(sub_role_name, '')))
    when 'head' then 10
    when 'leader' then 10
    when 'chairperson' then 10
    when 'co-head' then 20
    when 'co-leader' then 20
    when 'assistant head' then 30
    when 'assistant leader' then 30
    when 'assistant' then 40
    else 100
  end::smallint;
$$;

revoke all on function public.leadership_rank(text) from public, anon;
grant execute on function public.leadership_rank(text) to authenticated, service_role;

alter table public.profiles enable row level security;
alter table public.people enable row level security;
alter table public.person_external_ids enable row level security;
alter table public.roles enable row level security;
alter table public.sub_roles enable row level security;
alter table public.terms enable row level security;
alter table public.assignments enable row level security;
alter table public.assignment_external_ids enable row level security;
alter table public.import_runs enable row level security;
alter table public.import_rows enable row level security;
alter table public.import_conflicts enable row level security;
alter table public.audit_log enable row level security;
alter table public.webhook_deliveries enable row level security;

create policy profiles_read
on public.profiles for select
to authenticated
using (
  user_id = (select auth.uid())
  or private.has_ministry_role(array['admin'])
);

create policy profiles_admin_update
on public.profiles for update
to authenticated
using (private.has_ministry_role(array['admin']))
with check (private.has_ministry_role(array['admin']));

create policy people_authenticated_read
on public.people for select
to authenticated
using (private.has_ministry_role(array['admin', 'editor', 'viewer']));

create policy people_editor_insert
on public.people for insert
to authenticated
with check (private.has_ministry_role(array['admin', 'editor']));

create policy people_editor_update
on public.people for update
to authenticated
using (private.has_ministry_role(array['admin', 'editor']))
with check (private.has_ministry_role(array['admin', 'editor']));

create policy people_admin_delete
on public.people for delete
to authenticated
using (private.has_ministry_role(array['admin']));

create policy people_public_read
on public.people for select
to anon
using (is_public and is_active);

create policy external_ids_authenticated_read
on public.person_external_ids for select
to authenticated
using (private.has_ministry_role(array['admin', 'editor', 'viewer']));

create policy external_ids_editor_insert
on public.person_external_ids for insert
to authenticated
with check (private.has_ministry_role(array['admin', 'editor']));

create policy external_ids_editor_update
on public.person_external_ids for update
to authenticated
using (private.has_ministry_role(array['admin', 'editor']))
with check (private.has_ministry_role(array['admin', 'editor']));

create policy external_ids_admin_delete
on public.person_external_ids for delete
to authenticated
using (private.has_ministry_role(array['admin']));

create policy roles_authenticated_read
on public.roles for select
to authenticated
using (private.has_ministry_role(array['admin', 'editor', 'viewer']));

create policy roles_editor_insert
on public.roles for insert
to authenticated
with check (private.has_ministry_role(array['admin', 'editor']));

create policy roles_editor_update
on public.roles for update
to authenticated
using (private.has_ministry_role(array['admin', 'editor']))
with check (private.has_ministry_role(array['admin', 'editor']));

create policy roles_admin_delete
on public.roles for delete
to authenticated
using (private.has_ministry_role(array['admin']));

create policy roles_public_read
on public.roles for select
to anon
using (is_public and is_active);

create policy sub_roles_authenticated_read
on public.sub_roles for select
to authenticated
using (private.has_ministry_role(array['admin', 'editor', 'viewer']));

create policy sub_roles_editor_insert
on public.sub_roles for insert
to authenticated
with check (private.has_ministry_role(array['admin', 'editor']));

create policy sub_roles_editor_update
on public.sub_roles for update
to authenticated
using (private.has_ministry_role(array['admin', 'editor']))
with check (private.has_ministry_role(array['admin', 'editor']));

create policy sub_roles_admin_delete
on public.sub_roles for delete
to authenticated
using (private.has_ministry_role(array['admin']));

create policy sub_roles_public_read
on public.sub_roles for select
to anon
using (is_active);

create policy terms_authenticated_read
on public.terms for select
to authenticated
using (private.has_ministry_role(array['admin', 'editor', 'viewer']));

create policy terms_editor_insert
on public.terms for insert
to authenticated
with check (private.has_ministry_role(array['admin', 'editor']));

create policy terms_editor_update
on public.terms for update
to authenticated
using (private.has_ministry_role(array['admin', 'editor']))
with check (private.has_ministry_role(array['admin', 'editor']));

create policy terms_admin_delete
on public.terms for delete
to authenticated
using (private.has_ministry_role(array['admin']));

create policy terms_public_read
on public.terms for select
to anon
using (is_active);

create policy assignments_authenticated_read
on public.assignments for select
to authenticated
using (private.has_ministry_role(array['admin', 'editor', 'viewer']));

create policy assignments_editor_insert
on public.assignments for insert
to authenticated
with check (private.has_ministry_role(array['admin', 'editor']));

create policy assignments_editor_update
on public.assignments for update
to authenticated
using (private.has_ministry_role(array['admin', 'editor']))
with check (private.has_ministry_role(array['admin', 'editor']));

create policy assignments_admin_delete
on public.assignments for delete
to authenticated
using (private.has_ministry_role(array['admin']));

create policy assignments_public_read
on public.assignments for select
to anon
using (is_public and status = 'active');

create policy assignment_external_ids_authenticated_read
on public.assignment_external_ids for select
to authenticated
using (private.has_ministry_role(array['admin', 'editor', 'viewer']));

create policy assignment_external_ids_editor_insert
on public.assignment_external_ids for insert
to authenticated
with check (private.has_ministry_role(array['admin', 'editor']));

create policy assignment_external_ids_editor_update
on public.assignment_external_ids for update
to authenticated
using (private.has_ministry_role(array['admin', 'editor']))
with check (private.has_ministry_role(array['admin', 'editor']));

create policy assignment_external_ids_admin_delete
on public.assignment_external_ids for delete
to authenticated
using (private.has_ministry_role(array['admin']));

create policy import_runs_authenticated_read
on public.import_runs for select
to authenticated
using (private.has_ministry_role(array['admin', 'editor', 'viewer']));

create policy import_runs_editor_insert
on public.import_runs for insert
to authenticated
with check (
  private.has_ministry_role(array['admin', 'editor'])
  and (started_by is null or started_by = (select auth.uid()))
);

create policy import_runs_editor_update
on public.import_runs for update
to authenticated
using (private.has_ministry_role(array['admin', 'editor']))
with check (private.has_ministry_role(array['admin', 'editor']));

create policy import_detail_authenticated_read
on public.import_rows for select
to authenticated
using (private.has_ministry_role(array['admin', 'editor', 'viewer']));

create policy import_rows_editor_insert
on public.import_rows for insert
to authenticated
with check (private.has_ministry_role(array['admin', 'editor']));

create policy conflicts_authenticated_read
on public.import_conflicts for select
to authenticated
using (private.has_ministry_role(array['admin', 'editor', 'viewer']));

create policy conflicts_editor_insert
on public.import_conflicts for insert
to authenticated
with check (private.has_ministry_role(array['admin', 'editor']));

create policy conflicts_editor_update
on public.import_conflicts for update
to authenticated
using (private.has_ministry_role(array['admin', 'editor']))
with check (private.has_ministry_role(array['admin', 'editor']));

create policy audit_admin_read
on public.audit_log for select
to authenticated
using (private.has_ministry_role(array['admin']));

create policy webhook_deliveries_admin_read
on public.webhook_deliveries for select
to authenticated
using (private.has_ministry_role(array['admin']));

grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.people to authenticated;
grant select, insert, update, delete on public.person_external_ids to authenticated;
grant select, insert, update, delete on public.roles to authenticated;
grant select, insert, update, delete on public.sub_roles to authenticated;
grant select, insert, update, delete on public.terms to authenticated;
grant select, insert, update, delete on public.assignments to authenticated;
grant select, insert, update, delete on public.assignment_external_ids to authenticated;
grant select, insert, update on public.import_runs to authenticated;
grant select, insert on public.import_rows to authenticated;
grant select, insert, update on public.import_conflicts to authenticated;
grant select on public.audit_log to authenticated;
grant select on public.webhook_deliveries to authenticated;

grant all on public.profiles to service_role;
grant all on public.people to service_role;
grant all on public.person_external_ids to service_role;
grant all on public.roles to service_role;
grant all on public.sub_roles to service_role;
grant all on public.terms to service_role;
grant all on public.assignments to service_role;
grant all on public.assignment_external_ids to service_role;
grant all on public.import_runs to service_role;
grant all on public.import_rows to service_role;
grant all on public.import_conflicts to service_role;
grant all on public.audit_log to service_role;
grant all on public.webhook_deliveries to service_role;
grant usage, select on sequence public.audit_log_id_seq to service_role;

grant select (
  id, first_name, preferred_name, last_name, is_public, is_active
)
  on public.people to anon;
grant select (
  id, name, display_order, is_public, is_active
)
  on public.roles to anon;
grant select (id, role_id, name, leadership_rank)
  on public.sub_roles to anon;
grant select (id, name, start_date, end_date, term_type)
  on public.terms to anon;
grant select (
  id, person_id, role_id, sub_role_id, term_id, vote_date, is_public, status
)
  on public.assignments to anon;

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
  a.updated_at
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
  a.vote_date
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

grant select on public.assignment_details to authenticated, service_role;
grant select on public.public_directory_entries to anon, authenticated, service_role;

create or replace function public.merge_person_from_source(
  p_source_system text,
  p_external_id text,
  p_record jsonb,
  p_import_run_id uuid default null,
  p_row_number integer default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_person_id uuid;
  v_linked boolean := false;
  v_first_name text := nullif(btrim(p_record ->> 'first_name'), '');
  v_last_name text := nullif(btrim(p_record ->> 'last_name'), '');
  v_email text := nullif(btrim(p_record ->> 'email'), '');
  v_mobile text := nullif(btrim(p_record ->> 'mobile_phone'), '');
  v_home text := nullif(btrim(p_record ->> 'home_phone'), '');
  v_norm_name text;
  v_norm_email text;
  v_norm_phone text;
  v_candidates uuid[];
  v_existing public.people%rowtype;
  v_conflicts jsonb := '{}'::jsonb;
  v_outcome text := 'updated';
  v_import_row_id uuid;
begin
  if nullif(btrim(p_source_system), '') is null
    or nullif(btrim(p_external_id), '') is null then
    raise exception 'A source system and external ID are required.';
  end if;

  if v_first_name is null or v_last_name is null then
    raise exception 'First and last name are required.';
  end if;

  v_norm_name := lower(
    regexp_replace(v_first_name || ' ' || v_last_name, '[^a-zA-Z0-9]+', '', 'g')
  );
  v_norm_email := lower(regexp_replace(coalesce(v_email, ''), '[[:space:]]+', '', 'g'));
  v_norm_phone := regexp_replace(
    coalesce(v_mobile, v_home, ''),
    '[^0-9]+',
    '',
    'g'
  );

  select person_id
  into v_person_id
  from public.person_external_ids
  where source_system = p_source_system
    and external_id = p_external_id;

  v_linked := v_person_id is not null;

  if v_person_id is null then
    select coalesce(array_agg(id order by created_at), '{}'::uuid[])
    into v_candidates
    from public.people
    where normalized_name = v_norm_name
      and (
        (v_norm_email <> '' and normalized_email = v_norm_email)
        or
        (v_norm_phone <> '' and normalized_phone = v_norm_phone)
      );

    if cardinality(v_candidates) = 1 then
      v_person_id := v_candidates[1];
    elsif cardinality(v_candidates) > 1 then
      if p_import_run_id is not null then
        insert into public.import_rows (
          import_run_id, row_number, source_external_id, outcome, message, raw_record
        )
        values (
          p_import_run_id,
          p_row_number,
          p_external_id,
          'conflict',
          'More than one person matched the incoming name and contact details.',
          p_record
        )
        returning id into v_import_row_id;

        insert into public.import_conflicts (
          import_run_id,
          import_row_id,
          candidate_person_ids,
          conflict_type,
          incoming_values
        )
        values (
          p_import_run_id,
          v_import_row_id,
          v_candidates,
          'ambiguous_person',
          p_record
        );
      end if;

      return jsonb_build_object(
        'outcome', 'conflict',
        'reason', 'ambiguous_person',
        'candidate_person_ids', v_candidates
      );
    else
      select coalesce(array_agg(id order by created_at), '{}'::uuid[])
      into v_candidates
      from public.people
      where normalized_name = v_norm_name;

      if cardinality(v_candidates) > 0 then
        if p_import_run_id is not null then
          insert into public.import_rows (
            import_run_id, row_number, source_external_id, outcome, message, raw_record
          )
          values (
            p_import_run_id,
            p_row_number,
            p_external_id,
            'conflict',
            'A name match exists, but there is not enough identifying information to merge safely.',
            p_record
          )
          returning id into v_import_row_id;

          insert into public.import_conflicts (
            import_run_id,
            import_row_id,
            candidate_person_ids,
            conflict_type,
            incoming_values
          )
          values (
            p_import_run_id,
            v_import_row_id,
            v_candidates,
            'ambiguous_person',
            p_record
          );
        end if;

        return jsonb_build_object(
          'outcome', 'conflict',
          'reason', 'name_only_match',
          'candidate_person_ids', v_candidates
        );
      end if;
    end if;
  end if;

  if v_person_id is null then
    insert into public.people (
      first_name,
      middle_name,
      last_name,
      preferred_name,
      suffix,
      email,
      mobile_phone,
      home_phone,
      address_line_1,
      address_line_2,
      city,
      state_region,
      postal_code,
      country_code,
      is_active,
      source_updated_at
    )
    values (
      v_first_name,
      nullif(btrim(p_record ->> 'middle_name'), ''),
      v_last_name,
      nullif(btrim(p_record ->> 'preferred_name'), ''),
      nullif(btrim(p_record ->> 'suffix'), ''),
      v_email,
      v_mobile,
      v_home,
      nullif(btrim(p_record ->> 'address_line_1'), ''),
      nullif(btrim(p_record ->> 'address_line_2'), ''),
      nullif(btrim(p_record ->> 'city'), ''),
      nullif(btrim(p_record ->> 'state_region'), ''),
      nullif(btrim(p_record ->> 'postal_code'), ''),
      nullif(btrim(p_record ->> 'country_code'), ''),
      coalesce(nullif(p_record ->> 'is_active', '')::boolean, true),
      nullif(p_record ->> 'source_updated_at', '')::timestamptz
    )
    returning id into v_person_id;

    v_outcome := 'inserted';
  else
    select *
    into v_existing
    from public.people
    where id = v_person_id;

    if v_existing.email is not null and v_email is not null
      and lower(v_existing.email) <> lower(v_email) then
      v_conflicts := v_conflicts || jsonb_build_object(
        'email',
        jsonb_build_object('existing', v_existing.email, 'incoming', v_email)
      );
    end if;

    if v_existing.mobile_phone is not null and v_mobile is not null
      and regexp_replace(v_existing.mobile_phone, '[^0-9]+', '', 'g')
        <> regexp_replace(v_mobile, '[^0-9]+', '', 'g') then
      v_conflicts := v_conflicts || jsonb_build_object(
        'mobile_phone',
        jsonb_build_object('existing', v_existing.mobile_phone, 'incoming', v_mobile)
      );
    end if;

    if p_source_system = 'planning_center' and v_linked then
      update public.people
      set
        first_name = coalesce(v_first_name, first_name),
        middle_name = coalesce(nullif(btrim(p_record ->> 'middle_name'), ''), middle_name),
        last_name = coalesce(v_last_name, last_name),
        preferred_name = coalesce(
          nullif(btrim(p_record ->> 'preferred_name'), ''),
          preferred_name
        ),
        suffix = coalesce(nullif(btrim(p_record ->> 'suffix'), ''), suffix),
        email = coalesce(v_email, email),
        mobile_phone = coalesce(v_mobile, mobile_phone),
        home_phone = coalesce(v_home, home_phone),
        address_line_1 = coalesce(
          nullif(btrim(p_record ->> 'address_line_1'), ''),
          address_line_1
        ),
        address_line_2 = coalesce(
          nullif(btrim(p_record ->> 'address_line_2'), ''),
          address_line_2
        ),
        city = coalesce(nullif(btrim(p_record ->> 'city'), ''), city),
        state_region = coalesce(
          nullif(btrim(p_record ->> 'state_region'), ''),
          state_region
        ),
        postal_code = coalesce(
          nullif(btrim(p_record ->> 'postal_code'), ''),
          postal_code
        ),
        country_code = coalesce(
          nullif(btrim(p_record ->> 'country_code'), ''),
          country_code
        ),
        is_active = coalesce(
          nullif(p_record ->> 'is_active', '')::boolean,
          is_active
        ),
        source_updated_at = coalesce(
          nullif(p_record ->> 'source_updated_at', '')::timestamptz,
          source_updated_at
        )
      where id = v_person_id;
    else
      update public.people
      set
        middle_name = coalesce(middle_name, nullif(btrim(p_record ->> 'middle_name'), '')),
        preferred_name = coalesce(
          preferred_name,
          nullif(btrim(p_record ->> 'preferred_name'), '')
        ),
        suffix = coalesce(suffix, nullif(btrim(p_record ->> 'suffix'), '')),
        email = coalesce(email, v_email),
        mobile_phone = coalesce(mobile_phone, v_mobile),
        home_phone = coalesce(home_phone, v_home),
        address_line_1 = coalesce(
          address_line_1,
          nullif(btrim(p_record ->> 'address_line_1'), '')
        ),
        address_line_2 = coalesce(
          address_line_2,
          nullif(btrim(p_record ->> 'address_line_2'), '')
        ),
        city = coalesce(city, nullif(btrim(p_record ->> 'city'), '')),
        state_region = coalesce(
          state_region,
          nullif(btrim(p_record ->> 'state_region'), '')
        ),
        postal_code = coalesce(
          postal_code,
          nullif(btrim(p_record ->> 'postal_code'), '')
        ),
        country_code = coalesce(
          country_code,
          nullif(btrim(p_record ->> 'country_code'), '')
        )
      where id = v_person_id;
    end if;
  end if;

  insert into public.person_external_ids (
    person_id,
    source_system,
    external_id,
    source_updated_at,
    source_payload
  )
  values (
    v_person_id,
    p_source_system,
    p_external_id,
    nullif(p_record ->> 'source_updated_at', '')::timestamptz,
    p_record
  )
  on conflict (source_system, external_id)
  do update set
    person_id = excluded.person_id,
    source_updated_at = excluded.source_updated_at,
    source_payload = excluded.source_payload;

  if p_import_run_id is not null then
    insert into public.import_rows (
      import_run_id,
      row_number,
      source_external_id,
      person_id,
      outcome,
      message,
      raw_record
    )
    values (
      p_import_run_id,
      p_row_number,
      p_external_id,
      v_person_id,
      v_outcome,
      case
        when v_conflicts = '{}'::jsonb then null
        else 'Existing values were preserved and recorded for review.'
      end,
      p_record
    )
    returning id into v_import_row_id;

    if v_conflicts <> '{}'::jsonb then
      insert into public.import_conflicts (
        import_run_id,
        import_row_id,
        candidate_person_ids,
        conflict_type,
        incoming_values,
        existing_values
      )
      values (
        p_import_run_id,
        v_import_row_id,
        array[v_person_id],
        'field_mismatch',
        p_record,
        v_conflicts
      );
    end if;
  end if;

  return jsonb_build_object(
    'outcome', v_outcome,
    'person_id', v_person_id,
    'conflicts', v_conflicts
  );
exception
  when others then
    if p_import_run_id is not null then
      insert into public.import_rows (
        import_run_id, row_number, source_external_id, outcome, message, raw_record
      )
      values (
        p_import_run_id,
        p_row_number,
        p_external_id,
        'error',
        sqlerrm,
        p_record
      );
      return jsonb_build_object(
        'outcome', 'error',
        'message', sqlerrm
      );
    end if;
    raise;
end;
$$;

revoke all on function public.merge_person_from_source(text, text, jsonb, uuid, integer)
  from public, anon;
grant execute on function public.merge_person_from_source(text, text, jsonb, uuid, integer)
  to authenticated, service_role;

create or replace function public.upsert_assignment_from_source(
  p_source_system text,
  p_external_id text,
  p_record jsonb,
  p_import_run_id uuid default null,
  p_row_number integer default null
)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_assignment_id uuid;
  v_person_id uuid;
  v_person_candidates uuid[];
  v_role_id uuid;
  v_sub_role_id uuid;
  v_term_id uuid;
  v_role_name text := nullif(btrim(p_record ->> 'role_name'), '');
  v_sub_role_name text := nullif(btrim(p_record ->> 'sub_role_name'), '');
  v_term_name text := nullif(btrim(p_record ->> 'term_name'), '');
  v_person_name text := nullif(btrim(p_record ->> 'person_name'), '');
  v_person_norm text;
  v_vote_date date := nullif(p_record ->> 'vote_date', '')::date;
  v_outcome text := 'updated';
  v_import_row_id uuid;
begin
  if v_role_name is null or v_person_name is null then
    raise exception 'Person name and role name are required.';
  end if;

  v_person_norm := lower(
    regexp_replace(v_person_name, '[^a-zA-Z0-9]+', '', 'g')
  );

  select coalesce(array_agg(id order by created_at), '{}'::uuid[])
  into v_person_candidates
  from public.people
  where normalized_name = v_person_norm;

  if cardinality(v_person_candidates) <> 1 then
    if p_import_run_id is not null then
      insert into public.import_rows (
        import_run_id, row_number, source_external_id, outcome, message, raw_record
      )
      values (
        p_import_run_id,
        p_row_number,
        p_external_id,
        'conflict',
        case
          when cardinality(v_person_candidates) = 0
            then 'No person matched this assignment name.'
          else 'More than one person matched this assignment name.'
        end,
        p_record
      )
      returning id into v_import_row_id;

      insert into public.import_conflicts (
        import_run_id,
        import_row_id,
        candidate_person_ids,
        conflict_type,
        incoming_values
      )
      values (
        p_import_run_id,
        v_import_row_id,
        v_person_candidates,
        case
          when cardinality(v_person_candidates) = 0 then 'missing_person'
          else 'ambiguous_person'
        end,
        p_record
      );
    end if;

    return jsonb_build_object(
      'outcome', 'conflict',
      'reason', case
        when cardinality(v_person_candidates) = 0 then 'missing_person'
        else 'ambiguous_person'
      end,
      'candidate_person_ids', v_person_candidates
    );
  end if;

  v_person_id := v_person_candidates[1];

  select id into v_role_id
  from public.roles
  where lower(btrim(name)) = lower(v_role_name);

  if v_role_id is null then
    insert into public.roles (name)
    values (v_role_name)
    returning id into v_role_id;
  end if;

  if v_sub_role_name is not null then
    select id into v_sub_role_id
    from public.sub_roles
    where role_id is null
      and lower(btrim(name)) = lower(v_sub_role_name);

    if v_sub_role_id is null then
      insert into public.sub_roles (name, leadership_rank)
      values (
        v_sub_role_name,
        public.leadership_rank(v_sub_role_name)
      )
      returning id into v_sub_role_id;
    end if;
  end if;

  if v_term_name is not null then
    select id into v_term_id
    from public.terms
    where lower(btrim(name)) = lower(v_term_name);

    if v_term_id is null then
      if p_import_run_id is not null then
        insert into public.import_rows (
          import_run_id, row_number, source_external_id, outcome, message, raw_record
        )
        values (
          p_import_run_id,
          p_row_number,
          p_external_id,
          'conflict',
          'The assignment references a term that has not been created.',
          p_record
        )
        returning id into v_import_row_id;

        insert into public.import_conflicts (
          import_run_id,
          import_row_id,
          candidate_person_ids,
          conflict_type,
          incoming_values
        )
        values (
          p_import_run_id,
          v_import_row_id,
          array[v_person_id],
          'invalid_term',
          p_record
        );
      end if;

      return jsonb_build_object(
        'outcome', 'conflict',
        'reason', 'invalid_term',
        'term_name', v_term_name
      );
    end if;
  end if;

  select assignment_id
  into v_assignment_id
  from public.assignment_external_ids
  where source_system = p_source_system
    and external_id = p_external_id;

  if v_assignment_id is null then
    select id
    into v_assignment_id
    from public.assignments
    where person_id = v_person_id
      and role_id = v_role_id
      and sub_role_id is not distinct from v_sub_role_id
      and term_id is not distinct from v_term_id;
  end if;

  if v_assignment_id is null then
    insert into public.assignments (
      person_id,
      role_id,
      sub_role_id,
      term_id,
      vote_date,
      notes
    )
    values (
      v_person_id,
      v_role_id,
      v_sub_role_id,
      v_term_id,
      v_vote_date,
      nullif(btrim(p_record ->> 'notes'), '')
    )
    returning id into v_assignment_id;
    v_outcome := 'inserted';
  else
    update public.assignments
    set
      vote_date = coalesce(v_vote_date, vote_date),
      notes = coalesce(nullif(btrim(p_record ->> 'notes'), ''), notes)
    where id = v_assignment_id;
  end if;

  insert into public.assignment_external_ids (
    assignment_id,
    source_system,
    external_id,
    source_payload
  )
  values (
    v_assignment_id,
    p_source_system,
    p_external_id,
    p_record
  )
  on conflict (source_system, external_id)
  do update set
    assignment_id = excluded.assignment_id,
    source_payload = excluded.source_payload;

  if p_import_run_id is not null then
    insert into public.import_rows (
      import_run_id,
      row_number,
      source_external_id,
      assignment_id,
      person_id,
      outcome,
      raw_record
    )
    values (
      p_import_run_id,
      p_row_number,
      p_external_id,
      v_assignment_id,
      v_person_id,
      v_outcome,
      p_record
    );
  end if;

  return jsonb_build_object(
    'outcome', v_outcome,
    'assignment_id', v_assignment_id,
    'person_id', v_person_id
  );
exception
  when others then
    if p_import_run_id is not null then
      insert into public.import_rows (
        import_run_id, row_number, source_external_id, outcome, message, raw_record
      )
      values (
        p_import_run_id,
        p_row_number,
        p_external_id,
        'error',
        sqlerrm,
        p_record
      );
      return jsonb_build_object(
        'outcome', 'error',
        'message', sqlerrm
      );
    end if;
    raise;
end;
$$;

revoke all on function public.upsert_assignment_from_source(text, text, jsonb, uuid, integer)
  from public, anon;
grant execute on function public.upsert_assignment_from_source(text, text, jsonb, uuid, integer)
  to authenticated, service_role;
