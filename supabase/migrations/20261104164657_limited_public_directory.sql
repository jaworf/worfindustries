-- Public visitors receive exactly three approved display fields.
-- The old broad view remains for compatibility inside the database, but is no
-- longer directly readable anonymously. Applied migrations remain unchanged.
revoke select on public.public_directory_entries from public,anon;
create function public.limited_public_directory(p_slug text)
returns table(ministry text,volunteer text,term text)
language sql stable security definer set search_path='' as $$
 select distinct e.role_name,e.person_name,
 coalesce(nullif(e.term_name,''),case when e.start_date is not null and e.end_date is not null then to_char(e.start_date,'Mon DD, YYYY')||' - '||to_char(e.end_date,'Mon DD, YYYY') when e.end_date is not null then 'Through '||to_char(e.end_date,'Mon DD, YYYY') else 'Ongoing' end)
 from public.public_directory_entries e
 where e.church_slug=p_slug and p_slug ~ '^[a-z0-9][a-z0-9-]{0,79}$'
 order by 1,2,3;
$$;
revoke all on function public.limited_public_directory(text) from public;
grant execute on function public.limited_public_directory(text) to anon,authenticated,service_role;
comment on function public.limited_public_directory(text) is 'Intentional public read-only directory: only ministry, volunteer name and term, filtered by the existing active/public sharing rules and church slug.';
