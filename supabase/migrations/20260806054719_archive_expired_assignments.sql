-- Archive active volunteer assignments after their term's final day. Archived
-- assignments remain available in People Directory history but are excluded
-- from current directories, reports, the vote queue, and the public view.

create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

create index if not exists assignments_active_term_idx
on public.assignments (term_id)
where status = 'active' and archived_at is null;

create index if not exists terms_end_date_idx
on public.terms (end_date)
where end_date is not null;

create or replace function public.archive_expired_assignments()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  archived_count integer;
begin
  update public.assignments a
  set status = 'completed',
      updated_at = now()
  from public.terms t
  where t.id = a.term_id
    and a.status = 'active'
    and a.archived_at is null
    and t.end_date is not null
    and t.end_date < current_date;

  get diagnostics archived_count = row_count;
  return archived_count;
end;
$$;

comment on function public.archive_expired_assignments() is
  'Archives active volunteer assignments on the day after their term ends.';

revoke all on function public.archive_expired_assignments() from public;
revoke all on function public.archive_expired_assignments()
from anon, authenticated;

-- Keep deployment idempotent: replace this app-owned job without disturbing
-- any other Supabase Cron jobs in the project.
select cron.unschedule(jobid)
from cron.job
where jobname = 'archive-expired-ministry-assignments';

select cron.schedule(
  'archive-expired-ministry-assignments',
  '10 8 * * *',
  $command$select public.archive_expired_assignments();$command$
);

-- Reconcile any already-expired records immediately when this migration is
-- applied instead of waiting for the next scheduled run.
select public.archive_expired_assignments();

do $$
begin
  if exists (
    select 1
    from public.assignments a
    join public.terms t on t.id = a.term_id
    where a.status = 'active'
      and a.archived_at is null
      and t.end_date < current_date
  ) then
    raise exception 'An expired active assignment remained after reconciliation.';
  end if;

  if not exists (
    select 1
    from cron.job
    where jobname = 'archive-expired-ministry-assignments'
      and active
  ) then
    raise exception 'The automatic assignment archive job was not scheduled.';
  end if;
end;
$$;
