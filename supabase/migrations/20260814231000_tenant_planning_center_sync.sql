-- Service-role-only Planning Center merge, explicitly scoped to one church.

create or replace function public.sync_planning_center_person_for_church(
  p_church_id uuid,
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
  v_first_name text := nullif(btrim(p_record ->> 'first_name'), '');
  v_middle_name text := nullif(btrim(p_record ->> 'middle_name'), '');
  v_last_name text := nullif(btrim(p_record ->> 'last_name'), '');
  v_preferred_name text := nullif(btrim(p_record ->> 'preferred_name'), '');
  v_suffix text := nullif(btrim(p_record ->> 'suffix'), '');
  v_email text := nullif(btrim(p_record ->> 'email'), '');
  v_mobile text := nullif(btrim(p_record ->> 'mobile_phone'), '');
  v_home text := nullif(btrim(p_record ->> 'home_phone'), '');
  v_address_line_1 text := nullif(btrim(p_record ->> 'address_line_1'), '');
  v_address_line_2 text := nullif(btrim(p_record ->> 'address_line_2'), '');
  v_city text := nullif(btrim(p_record ->> 'city'), '');
  v_state_region text := nullif(btrim(p_record ->> 'state_region'), '');
  v_postal_code text := nullif(btrim(p_record ->> 'postal_code'), '');
  v_country_code text := nullif(btrim(p_record ->> 'country_code'), '');
  v_membership_status text := nullif(btrim(p_record ->> 'membership_status'), '');
  v_is_active boolean := coalesce(nullif(p_record ->> 'is_active', '')::boolean, true);
  v_source_created_at timestamptz := nullif(p_record ->> 'source_created_at', '')::timestamptz;
  v_source_updated_at timestamptz := nullif(p_record ->> 'source_updated_at', '')::timestamptz;
  v_norm_name text;
  v_norm_email text;
  v_norm_phone text;
  v_candidates uuid[] := '{}'::uuid[];
  v_existing public.people%rowtype;
  v_outcome text := 'updated';
  v_changed boolean := false;
  v_import_row_id uuid;
begin
  if p_church_id is null or not exists (select 1 from public.churches where id = p_church_id and is_active) then
    raise exception 'A valid active church is required.';
  end if;
  if nullif(btrim(p_external_id), '') is null then
    raise exception 'A Planning Center person ID is required.';
  end if;
  if v_first_name is null or v_last_name is null then
    raise exception 'First and last name are required.';
  end if;
  if p_import_run_id is not null and not exists (
    select 1 from public.import_runs where id = p_import_run_id and church_id = p_church_id
  ) then
    raise exception 'The import run does not belong to this church.';
  end if;

  v_norm_name := lower(regexp_replace(v_first_name || ' ' || v_last_name, '[^a-zA-Z0-9]+', '', 'g'));
  v_norm_email := lower(regexp_replace(coalesce(v_email, ''), '[[:space:]]+', '', 'g'));
  v_norm_phone := regexp_replace(coalesce(v_mobile, v_home, ''), '[^0-9]+', '', 'g');

  select person_id into v_person_id
  from public.person_external_ids
  where church_id = p_church_id
    and source_system = 'planning_center'
    and external_id = p_external_id;

  if v_person_id is null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(
        p_church_id::text || ':planning_center:' || v_norm_name || ':' || v_norm_email || ':' || v_norm_phone,
        0
      )
    );

    select coalesce(array_agg(p.id order by p.created_at), '{}'::uuid[])
    into v_candidates
    from public.people p
    where p.church_id = p_church_id
      and p.normalized_name = v_norm_name
      and (
        (v_norm_email <> '' and p.normalized_email = v_norm_email)
        or (v_norm_phone <> '' and p.normalized_phone = v_norm_phone)
      )
      and not exists (
        select 1 from public.person_external_ids x
        where x.church_id = p_church_id
          and x.person_id = p.id
          and x.source_system = 'planning_center'
      );

    if cardinality(v_candidates) = 1 then
      v_person_id := v_candidates[1];
    elsif cardinality(v_candidates) > 1 then
      v_outcome := 'conflict';
    else
      select coalesce(array_agg(p.id order by p.created_at), '{}'::uuid[])
      into v_candidates
      from public.people p
      where p.church_id = p_church_id
        and p.normalized_name = v_norm_name
        and not exists (
          select 1 from public.person_external_ids x
          where x.church_id = p_church_id
            and x.person_id = p.id
            and x.source_system = 'planning_center'
        );
      if cardinality(v_candidates) > 0 then
        v_outcome := 'conflict';
      end if;
    end if;

    if v_outcome = 'conflict' then
      if p_import_run_id is not null then
        insert into public.import_rows (
          church_id, import_run_id, row_number, source_external_id,
          outcome, message, raw_record
        ) values (
          p_church_id, p_import_run_id, p_row_number, p_external_id,
          'conflict', 'A local person match requires review before Planning Center can be linked.', p_record
        ) returning id into v_import_row_id;
        insert into public.import_conflicts (
          church_id, import_run_id, import_row_id, candidate_person_ids,
          conflict_type, incoming_values
        ) values (
          p_church_id, p_import_run_id, v_import_row_id, v_candidates,
          'ambiguous_person', p_record
        );
      end if;
      return jsonb_build_object(
        'outcome', 'conflict',
        'reason', 'ambiguous_person',
        'candidate_person_ids', v_candidates
      );
    end if;
  end if;

  if v_person_id is null then
    insert into public.people (
      church_id, first_name, middle_name, last_name, preferred_name, suffix,
      email, mobile_phone, home_phone, address_line_1, address_line_2,
      city, state_region, postal_code, country_code, membership_status,
      is_active, source_created_at, source_updated_at
    ) values (
      p_church_id, v_first_name, v_middle_name, v_last_name, v_preferred_name, v_suffix,
      v_email, v_mobile, v_home, v_address_line_1, v_address_line_2,
      v_city, v_state_region, v_postal_code, v_country_code, v_membership_status,
      v_is_active, v_source_created_at, v_source_updated_at
    ) returning id into v_person_id;
    v_outcome := 'inserted';
  else
    select * into v_existing
    from public.people
    where id = v_person_id and church_id = p_church_id
    for update;

    v_changed :=
      v_existing.first_name is distinct from v_first_name
      or v_existing.middle_name is distinct from v_middle_name
      or v_existing.last_name is distinct from v_last_name
      or v_existing.preferred_name is distinct from v_preferred_name
      or v_existing.suffix is distinct from v_suffix
      or v_existing.email is distinct from v_email
      or v_existing.mobile_phone is distinct from v_mobile
      or v_existing.home_phone is distinct from v_home
      or v_existing.address_line_1 is distinct from v_address_line_1
      or v_existing.address_line_2 is distinct from v_address_line_2
      or v_existing.city is distinct from v_city
      or v_existing.state_region is distinct from v_state_region
      or v_existing.postal_code is distinct from v_postal_code
      or v_existing.country_code is distinct from v_country_code
      or v_existing.membership_status is distinct from v_membership_status
      or v_existing.is_active is distinct from v_is_active
      or v_existing.source_created_at is distinct from coalesce(v_source_created_at, v_existing.source_created_at)
      or v_existing.source_updated_at is distinct from coalesce(v_source_updated_at, v_existing.source_updated_at);

    if v_changed then
      update public.people set
        first_name = v_first_name,
        middle_name = v_middle_name,
        last_name = v_last_name,
        preferred_name = v_preferred_name,
        suffix = v_suffix,
        email = v_email,
        mobile_phone = v_mobile,
        home_phone = v_home,
        address_line_1 = v_address_line_1,
        address_line_2 = v_address_line_2,
        city = v_city,
        state_region = v_state_region,
        postal_code = v_postal_code,
        country_code = v_country_code,
        membership_status = v_membership_status,
        is_active = v_is_active,
        source_created_at = coalesce(v_source_created_at, source_created_at),
        source_updated_at = coalesce(v_source_updated_at, source_updated_at)
      where id = v_person_id and church_id = p_church_id;
      v_outcome := 'updated';
    else
      v_outcome := 'unchanged';
    end if;
  end if;

  insert into public.person_external_ids (
    church_id, person_id, source_system, external_id, source_updated_at, source_payload
  ) values (
    p_church_id, v_person_id, 'planning_center', p_external_id, v_source_updated_at, p_record
  )
  on conflict (church_id, source_system, external_id) do update set
    person_id = excluded.person_id,
    source_updated_at = excluded.source_updated_at,
    source_payload = excluded.source_payload;

  if p_import_run_id is not null then
    insert into public.import_rows (
      church_id, import_run_id, row_number, source_external_id,
      person_id, outcome, raw_record
    ) values (
      p_church_id, p_import_run_id, p_row_number, p_external_id,
      v_person_id, v_outcome, p_record
    );
  end if;

  return jsonb_build_object('outcome', v_outcome, 'person_id', v_person_id);
end;
$$;

revoke all on function public.sync_planning_center_person_for_church(uuid, text, jsonb, uuid, integer)
from public, anon, authenticated;
grant execute on function public.sync_planning_center_person_for_church(uuid, text, jsonb, uuid, integer)
to service_role;

