-- Multi-church tenancy, per-church Planning Center credentials, and an
-- isolated fictional dataset for App Review.

create table public.churches (
  id uuid primary key default extensions.gen_random_uuid(),
  name text not null check (btrim(name) <> ''),
  slug text not null check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  support_email text,
  public_directory_enabled boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (slug)
);

insert into public.churches (name, slug, support_email, public_directory_enabled)
values (
  'Pasco Riverview Adventist Church',
  'riverview',
  'jason.worf@riverviewadventist.org',
  true
)
on conflict (slug) do update set
  name = excluded.name,
  support_email = excluded.support_email,
  public_directory_enabled = excluded.public_directory_enabled;

insert into public.churches (name, slug, support_email, public_directory_enabled)
values (
  'Apple Review Test Church',
  'apple-review',
  'jason.worf@riverviewadventist.org',
  false
)
on conflict (slug) do update set
  name = excluded.name,
  support_email = excluded.support_email;

alter table public.profiles add column church_id uuid references public.churches (id);
alter table public.profiles add column is_platform_admin boolean not null default false;

update public.profiles
set church_id = (select id from public.churches where slug = 'riverview')
where church_id is null;

update public.profiles p
set is_platform_admin = true
from auth.users u
where u.id = p.user_id
  and lower(u.email) = 'jason.worf@riverviewadventist.org';

create or replace function private.current_church_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select church_id
  from public.profiles
  where user_id = (select auth.uid());
$$;

revoke all on function private.current_church_id() from public, anon;
grant execute on function private.current_church_id() to authenticated, service_role;

alter table public.people add column church_id uuid references public.churches (id) default private.current_church_id();
alter table public.person_external_ids add column church_id uuid references public.churches (id) default private.current_church_id();
alter table public.roles add column church_id uuid references public.churches (id) default private.current_church_id();
alter table public.sub_roles add column church_id uuid references public.churches (id) default private.current_church_id();
alter table public.terms add column church_id uuid references public.churches (id) default private.current_church_id();
alter table public.assignments add column church_id uuid references public.churches (id) default private.current_church_id();
alter table public.assignment_external_ids add column church_id uuid references public.churches (id) default private.current_church_id();
alter table public.import_runs add column church_id uuid references public.churches (id) default private.current_church_id();
alter table public.import_rows add column church_id uuid references public.churches (id) default private.current_church_id();
alter table public.import_conflicts add column church_id uuid references public.churches (id) default private.current_church_id();
alter table public.audit_log add column church_id uuid references public.churches (id) default private.current_church_id();
alter table public.webhook_deliveries add column church_id uuid references public.churches (id) default private.current_church_id();

do $$
declare
  v_riverview uuid := (select id from public.churches where slug = 'riverview');
begin
  update public.people set church_id = v_riverview where church_id is null;
  update public.person_external_ids x set church_id = p.church_id from public.people p where p.id = x.person_id and x.church_id is null;
  update public.roles set church_id = v_riverview where church_id is null;
  update public.sub_roles s set church_id = r.church_id from public.roles r where r.id = s.role_id and s.church_id is null;
  update public.sub_roles set church_id = v_riverview where church_id is null;
  update public.terms set church_id = v_riverview where church_id is null;
  update public.assignments a set church_id = p.church_id from public.people p where p.id = a.person_id and a.church_id is null;
  update public.assignment_external_ids x set church_id = a.church_id from public.assignments a where a.id = x.assignment_id and x.church_id is null;
  update public.import_runs set church_id = v_riverview where church_id is null;
  update public.import_rows x set church_id = r.church_id from public.import_runs r where r.id = x.import_run_id and x.church_id is null;
  update public.import_rows set church_id = v_riverview where church_id is null;
  update public.import_conflicts x set church_id = r.church_id from public.import_runs r where r.id = x.import_run_id and x.church_id is null;
  update public.import_conflicts set church_id = v_riverview where church_id is null;
  update public.audit_log set church_id = v_riverview where church_id is null;
  update public.webhook_deliveries set church_id = v_riverview where church_id is null;
end;
$$;

alter table public.people alter column church_id set not null;
alter table public.person_external_ids alter column church_id set not null;
alter table public.roles alter column church_id set not null;
alter table public.sub_roles alter column church_id set not null;
alter table public.terms alter column church_id set not null;
alter table public.assignments alter column church_id set not null;
alter table public.assignment_external_ids alter column church_id set not null;
alter table public.import_runs alter column church_id set not null;
alter table public.import_rows alter column church_id set not null;
alter table public.import_conflicts alter column church_id set not null;
alter table public.audit_log alter column church_id set not null;
alter table public.webhook_deliveries alter column church_id set not null;

create or replace function private.write_audit_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record_id uuid;
  v_church_id uuid;
begin
  if tg_op = 'DELETE' then
    v_record_id := old.id;
    v_church_id := old.church_id;
    insert into public.audit_log (
      church_id, table_name, record_id, operation, changed_by, old_values
    ) values (
      v_church_id, tg_table_name, v_record_id, tg_op, (select auth.uid()), to_jsonb(old)
    );
    return old;
  end if;

  v_record_id := new.id;
  v_church_id := new.church_id;
  insert into public.audit_log (
    church_id, table_name, record_id, operation, changed_by, old_values, new_values
  ) values (
    v_church_id,
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

alter table public.people add constraint people_id_church_unique unique (id, church_id);
alter table public.roles add constraint roles_id_church_unique unique (id, church_id);
alter table public.sub_roles add constraint sub_roles_id_church_unique unique (id, church_id);
alter table public.terms add constraint terms_id_church_unique unique (id, church_id);
alter table public.assignments add constraint assignments_id_church_unique unique (id, church_id);
alter table public.import_runs add constraint import_runs_id_church_unique unique (id, church_id);
alter table public.import_rows add constraint import_rows_id_church_unique unique (id, church_id);

alter table public.person_external_ids drop constraint person_external_ids_person_id_fkey;
alter table public.person_external_ids add constraint person_external_ids_person_church_fkey
  foreign key (person_id, church_id) references public.people (id, church_id) on delete cascade;
alter table public.sub_roles drop constraint sub_roles_role_id_fkey;
alter table public.sub_roles add constraint sub_roles_role_church_fkey
  foreign key (role_id, church_id) references public.roles (id, church_id) on delete cascade;
alter table public.assignments drop constraint assignments_person_id_fkey;
alter table public.assignments drop constraint assignments_role_id_fkey;
alter table public.assignments drop constraint assignments_sub_role_id_fkey;
alter table public.assignments drop constraint assignments_term_id_fkey;
alter table public.assignments add constraint assignments_person_church_fkey
  foreign key (person_id, church_id) references public.people (id, church_id) on delete restrict;
alter table public.assignments add constraint assignments_role_church_fkey
  foreign key (role_id, church_id) references public.roles (id, church_id) on delete restrict;
alter table public.assignments add constraint assignments_sub_role_church_fkey
  foreign key (sub_role_id, church_id) references public.sub_roles (id, church_id) on delete set null (sub_role_id);
alter table public.assignments add constraint assignments_term_church_fkey
  foreign key (term_id, church_id) references public.terms (id, church_id) on delete restrict;
alter table public.assignment_external_ids drop constraint assignment_external_ids_assignment_id_fkey;
alter table public.assignment_external_ids add constraint assignment_external_ids_assignment_church_fkey
  foreign key (assignment_id, church_id) references public.assignments (id, church_id) on delete cascade;
alter table public.import_rows drop constraint import_rows_import_run_id_fkey;
alter table public.import_rows drop constraint import_rows_person_id_fkey;
alter table public.import_rows drop constraint import_rows_assignment_id_fkey;
alter table public.import_rows add constraint import_rows_run_church_fkey
  foreign key (import_run_id, church_id) references public.import_runs (id, church_id) on delete cascade;
alter table public.import_rows add constraint import_rows_person_church_fkey
  foreign key (person_id, church_id) references public.people (id, church_id) on delete set null (person_id);
alter table public.import_rows add constraint import_rows_assignment_church_fkey
  foreign key (assignment_id, church_id) references public.assignments (id, church_id) on delete set null (assignment_id);
alter table public.import_conflicts drop constraint import_conflicts_import_run_id_fkey;
alter table public.import_conflicts drop constraint import_conflicts_import_row_id_fkey;
alter table public.import_conflicts add constraint import_conflicts_run_church_fkey
  foreign key (import_run_id, church_id) references public.import_runs (id, church_id) on delete cascade;
alter table public.import_conflicts add constraint import_conflicts_row_church_fkey
  foreign key (import_row_id, church_id) references public.import_rows (id, church_id) on delete cascade;

alter table public.person_external_ids drop constraint person_external_ids_source_system_external_id_key;
alter table public.person_external_ids add constraint person_external_ids_church_source_external_unique
  unique (church_id, source_system, external_id);
alter table public.assignment_external_ids drop constraint assignment_external_ids_source_system_external_id_key;
alter table public.assignment_external_ids add constraint assignment_external_ids_church_source_external_unique
  unique (church_id, source_system, external_id);
alter table public.webhook_deliveries drop constraint webhook_deliveries_source_system_delivery_id_key;
alter table public.webhook_deliveries add constraint webhook_deliveries_church_source_delivery_unique
  unique (church_id, source_system, delivery_id);

drop index public.roles_name_ci_unique;
create unique index roles_church_name_ci_unique on public.roles (church_id, lower(btrim(name)));
drop index public.sub_roles_name_ci_unique;
create unique index sub_roles_church_name_ci_unique on public.sub_roles (
  church_id,
  coalesce(role_id, '00000000-0000-0000-0000-000000000000'::uuid),
  lower(btrim(name))
);
drop index public.terms_name_ci_unique;
create unique index terms_church_name_ci_unique on public.terms (church_id, lower(btrim(name)));

create index profiles_church_idx on public.profiles (church_id, app_role);
create index people_church_name_idx on public.people (church_id, last_name, first_name);
create index roles_church_order_idx on public.roles (church_id, display_order, name);
create index assignments_church_status_idx on public.assignments (church_id, status);
create index import_runs_church_started_idx on public.import_runs (church_id, started_at desc);
create index audit_log_church_changed_idx on public.audit_log (church_id, changed_at desc);

create or replace function private.has_church_role(p_church_id uuid, allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    (select auth.uid()) is not null
    and exists (
      select 1 from public.profiles
      where user_id = (select auth.uid())
        and church_id = p_church_id
        and app_role = any (allowed_roles)
    );
$$;

revoke all on function private.has_church_role(uuid, text[]) from public, anon;
grant execute on function private.has_church_role(uuid, text[]) to authenticated, service_role;

create or replace function private.has_ministry_role(allowed_roles text[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where user_id = (select auth.uid())
      and church_id is not null
      and app_role = any (allowed_roles)
  );
$$;

create or replace function private.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles
    where user_id = (select auth.uid())
      and is_platform_admin
  );
$$;

revoke all on function private.is_platform_admin() from public, anon;
grant execute on function private.is_platform_admin() to authenticated, service_role;

create trigger churches_set_updated_at
before update on public.churches
for each row execute function private.set_updated_at();

alter table public.churches enable row level security;

do $$
declare p record;
begin
  for p in select schemaname, tablename, policyname from pg_policies where schemaname = 'public'
    and tablename in ('profiles','people','person_external_ids','roles','sub_roles','terms','assignments','assignment_external_ids','import_runs','import_rows','import_conflicts','audit_log','webhook_deliveries')
  loop
    execute format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end;
$$;

create policy churches_member_read on public.churches for select to authenticated
using (
  id = private.current_church_id()
  or private.is_platform_admin()
);
create policy churches_admin_update on public.churches for update to authenticated
using (private.has_church_role(id, array['admin']))
with check (private.has_church_role(id, array['admin']));

create policy profiles_tenant_read on public.profiles for select to authenticated
using (
  user_id = (select auth.uid())
  or church_id = private.current_church_id()
  or private.is_platform_admin()
);
create policy profiles_tenant_admin_update on public.profiles for update to authenticated
using (church_id is not null and private.has_church_role(church_id, array['admin']))
with check (church_id is not null and private.has_church_role(church_id, array['admin']));

do $$
declare t text;
begin
  foreach t in array array['people','person_external_ids','roles','sub_roles','terms','assignments','assignment_external_ids','import_runs','import_rows','import_conflicts']
  loop
    execute format('create policy %I on public.%I for select to authenticated using (private.has_church_role(church_id, array[''admin'',''editor'',''viewer'']))', t || '_tenant_read', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (private.has_church_role(church_id, array[''admin'',''editor'']))', t || '_tenant_insert', t);
    execute format('create policy %I on public.%I for update to authenticated using (private.has_church_role(church_id, array[''admin'',''editor''])) with check (private.has_church_role(church_id, array[''admin'',''editor'']))', t || '_tenant_update', t);
    execute format('create policy %I on public.%I for delete to authenticated using (private.has_church_role(church_id, array[''admin'']))', t || '_tenant_delete', t);
  end loop;
end;
$$;

create policy audit_log_tenant_admin_read on public.audit_log for select to authenticated
using (private.has_church_role(church_id, array['admin']));
create policy webhook_deliveries_tenant_admin_read on public.webhook_deliveries for select to authenticated
using (private.has_church_role(church_id, array['admin']));

-- Public directory access is explicitly opt-in per church and exposes only the
-- already-approved public columns through the view below.
create policy people_public_read on public.people for select to anon
using (is_public and is_active and exists (
  select 1 from public.churches c where c.id = church_id and c.public_directory_enabled and c.is_active
));
create policy roles_public_read on public.roles for select to anon
using (is_public and is_active and exists (
  select 1 from public.churches c where c.id = church_id and c.public_directory_enabled and c.is_active
));
create policy sub_roles_public_read on public.sub_roles for select to anon
using (is_active and exists (
  select 1 from public.churches c where c.id = church_id and c.public_directory_enabled and c.is_active
));
create policy terms_public_read on public.terms for select to anon
using (is_active and exists (
  select 1 from public.churches c where c.id = church_id and c.public_directory_enabled and c.is_active
));
create policy assignments_public_read on public.assignments for select to anon
using (is_public and status = 'active' and exists (
  select 1 from public.churches c where c.id = church_id and c.public_directory_enabled and c.is_active
));
create policy churches_public_directory_read on public.churches for select to anon
using (public_directory_enabled and is_active);

create table private.planning_center_connections (
  church_id uuid primary key references public.churches (id) on delete cascade,
  application_id_secret_id uuid not null,
  secret_secret_id uuid not null,
  configured_by uuid references auth.users (id) on delete set null,
  configured_at timestamptz not null default now(),
  last_synced_at timestamptz,
  last_sync_status text,
  last_sync_error text
);
revoke all on private.planning_center_connections from public, anon, authenticated;
grant all on private.planning_center_connections to service_role;

create or replace function public.configure_planning_center(
  p_application_id text,
  p_secret text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_church_id uuid := private.current_church_id();
  v_existing private.planning_center_connections%rowtype;
  v_app_secret_id uuid;
  v_secret_id uuid;
begin
  if v_church_id is null or not private.has_church_role(v_church_id, array['admin']) then
    raise exception 'Only a church administrator can configure Planning Center.';
  end if;
  if nullif(btrim(p_application_id), '') is null or nullif(btrim(p_secret), '') is null then
    raise exception 'Both the Personal Access Token application ID and secret are required.';
  end if;

  select * into v_existing from private.planning_center_connections where church_id = v_church_id;
  if v_existing.church_id is null then
    v_app_secret_id := vault.create_secret(btrim(p_application_id), null, 'Planning Center application ID');
    v_secret_id := vault.create_secret(btrim(p_secret), null, 'Planning Center personal access token secret');
    insert into private.planning_center_connections (
      church_id, application_id_secret_id, secret_secret_id, configured_by
    ) values (v_church_id, v_app_secret_id, v_secret_id, (select auth.uid()));
  else
    perform vault.update_secret(v_existing.application_id_secret_id, btrim(p_application_id));
    perform vault.update_secret(v_existing.secret_secret_id, btrim(p_secret));
    update private.planning_center_connections set
      configured_by = (select auth.uid()), configured_at = now(),
      last_sync_status = null, last_sync_error = null
    where church_id = v_church_id;
  end if;
  return jsonb_build_object('connected', true, 'configured_at', now());
end;
$$;

create or replace function public.planning_center_connection_status()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'connected', pc.church_id is not null,
    'configured_at', pc.configured_at,
    'last_synced_at', pc.last_synced_at,
    'last_sync_status', pc.last_sync_status,
    'last_sync_error', pc.last_sync_error
  )
  from (select private.current_church_id() as church_id) me
  left join private.planning_center_connections pc on pc.church_id = me.church_id
  where me.church_id is not null;
$$;

create or replace function public.get_planning_center_credentials(p_church_id uuid)
returns table (application_id text, secret text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce((select auth.role()), '') <> 'service_role' then
    raise exception 'Service role required.';
  end if;
  return query
  select app.decrypted_secret, sec.decrypted_secret
  from private.planning_center_connections pc
  join vault.decrypted_secrets app on app.id = pc.application_id_secret_id
  join vault.decrypted_secrets sec on sec.id = pc.secret_secret_id
  where pc.church_id = p_church_id;
end;
$$;

revoke all on function public.configure_planning_center(text, text) from public, anon;
grant execute on function public.configure_planning_center(text, text) to authenticated;
revoke all on function public.planning_center_connection_status() from public, anon;
grant execute on function public.planning_center_connection_status() to authenticated;
revoke all on function public.get_planning_center_credentials(uuid) from public, anon, authenticated;
grant execute on function public.get_planning_center_credentials(uuid) to service_role;

drop view if exists public.public_directory_entries;
drop view if exists public.assignment_details;

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
  (r.requires_vote or coalesce(sr.requires_vote, false)) as requires_vote,
  ((r.requires_vote or coalesce(sr.requires_vote, false)) and a.vote_date is null) as vote_missing,
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

create or replace view public.public_directory_entries
with (security_invoker = true, security_barrier = true)
as
select
  a.church_id,
  c.name as church_name,
  c.slug as church_slug,
  a.id,
  concat_ws(' ', coalesce(nullif(p.preferred_name, ''), p.first_name), p.last_name) as person_name,
  p.last_name,
  p.first_name,
  r.name as role_name,
  sr.name as sub_role_name,
  coalesce(sr.leadership_rank::integer, 100) as leadership_rank,
  t.name as term_name,
  t.start_date,
  t.end_date,
  a.vote_date,
  a.public_note as note
from public.assignments a
join public.churches c on c.id = a.church_id
join public.people p on p.id = a.person_id and p.church_id = a.church_id
join public.roles r on r.id = a.role_id and r.church_id = a.church_id
left join public.sub_roles sr on sr.id = a.sub_role_id and sr.church_id = a.church_id
left join public.terms t on t.id = a.term_id and t.church_id = a.church_id
where c.public_directory_enabled
  and c.is_active
  and a.is_public
  and a.status = 'active'
  and p.is_public
  and p.is_active
  and r.is_public
  and r.is_active;

grant select on public.churches to authenticated;
grant update (name, support_email, public_directory_enabled) on public.churches to authenticated;
revoke update on public.profiles from authenticated;
grant update (display_name, app_role) on public.profiles to authenticated;
grant select (id, name, slug, public_directory_enabled, is_active) on public.churches to anon;
grant select (church_id) on public.people, public.roles, public.sub_roles, public.terms, public.assignments to anon;
grant select on public.assignment_details to authenticated;
grant select on public.public_directory_entries to anon, authenticated;

-- Fictional data only. Reserved example.com addresses prevent accidental mail.
do $$
declare
  v_church uuid := (select id from public.churches where slug = 'apple-review');
  v_term uuid;
  v_deacon uuid;
  v_welcome uuid;
  v_food uuid;
  v_head uuid;
  v_member uuid;
  v_coordinator uuid;
  v_person uuid;
begin
  insert into public.terms (church_id, name, start_date, end_date, term_type)
  values (v_church, '2026–2027 Calendar Term', '2026-01-01', '2027-12-31', 'calendar')
  returning id into v_term;

  insert into public.roles (church_id, name, requires_vote, display_order)
  values (v_church, 'Deacon Team', true, 10)
  returning id into v_deacon;
  insert into public.roles (church_id, name, requires_vote, display_order)
  values (v_church, 'Welcome Team', false, 20)
  returning id into v_welcome;
  insert into public.roles (church_id, name, requires_vote, display_order)
  values (v_church, 'Community Meal', false, 30)
  returning id into v_food;

  insert into public.sub_roles (church_id, role_id, name, leadership_rank, requires_vote)
  values (v_church, v_deacon, 'Head', 10, true)
  returning id into v_head;
  insert into public.sub_roles (church_id, role_id, name, leadership_rank)
  values (v_church, v_deacon, 'Team Member', 100)
  returning id into v_member;
  insert into public.sub_roles (church_id, role_id, name, leadership_rank)
  values (v_church, v_welcome, 'Coordinator', 10)
  returning id into v_coordinator;

  insert into public.people (church_id, first_name, last_name, email, mobile_phone, membership_status, is_public, is_ordained_deacon)
  values (v_church, 'Avery', 'Bennett', 'avery.bennett@example.com', '509-555-0101', 'Member', true, true)
  returning id into v_person;
  insert into public.assignments (church_id, person_id, role_id, sub_role_id, term_id, vote_date, notes, status)
  values (v_church, v_person, v_deacon, v_head, v_term, '2026-01-10', 'Fictional App Review record.', 'active');

  insert into public.people (church_id, first_name, last_name, email, membership_status, is_public)
  values (v_church, 'Jordan', 'Kim', 'jordan.kim@example.com', 'Member', true)
  returning id into v_person;
  insert into public.assignments (church_id, person_id, role_id, sub_role_id, term_id, vote_date, status)
  values (v_church, v_person, v_deacon, v_member, v_term, null, 'active');

  insert into public.people (church_id, first_name, last_name, email, membership_status, is_public)
  values (v_church, 'Morgan', 'Lee', 'morgan.lee@example.com', 'Member', true)
  returning id into v_person;
  insert into public.assignments (church_id, person_id, role_id, sub_role_id, notes, note_is_public, status)
  values (v_church, v_person, v_welcome, v_coordinator, 'Coordinates the greeting schedule.', true, 'active');

  insert into public.people (church_id, first_name, last_name, email, membership_status, is_public)
  values
    (v_church, 'Riley', 'Patel', 'riley.patel@example.com', 'Member', true),
    (v_church, 'Casey', 'Rivera', 'casey.rivera@example.com', 'Guest', true),
    (v_church, 'Taylor', 'Nguyen', 'taylor.nguyen@example.com', 'Member', true);
end;
$$;
