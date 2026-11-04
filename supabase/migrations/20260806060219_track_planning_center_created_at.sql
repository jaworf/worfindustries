alter table public.people
add column if not exists source_created_at timestamptz;

comment on column public.people.source_created_at is
  'Planning Center People created_at timestamp. Used to prioritize genuinely new volunteer records.';

create or replace function public.mirror_planning_center_created_at()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source_created_at timestamptz :=
    nullif(new.source_payload ->> 'source_created_at', '')::timestamptz;
begin
  if new.source_system = 'planning_center' and v_source_created_at is not null then
    update public.people
    set source_created_at = v_source_created_at
    where id = new.person_id
      and source_created_at is distinct from v_source_created_at;
  end if;
  return new;
end;
$$;

revoke all on function public.mirror_planning_center_created_at() from public;
revoke all on function public.mirror_planning_center_created_at() from anon;
revoke all on function public.mirror_planning_center_created_at() from authenticated;

drop trigger if exists person_external_ids_mirror_source_created_at
on public.person_external_ids;

create trigger person_external_ids_mirror_source_created_at
after insert or update of person_id, source_system, source_payload
on public.person_external_ids
for each row
execute function public.mirror_planning_center_created_at();

update public.people p
set source_created_at = nullif(x.source_payload ->> 'source_created_at', '')::timestamptz
from public.person_external_ids x
where x.person_id = p.id
  and x.source_system = 'planning_center'
  and nullif(x.source_payload ->> 'source_created_at', '') is not null
  and p.source_created_at is distinct from
    nullif(x.source_payload ->> 'source_created_at', '')::timestamptz;
