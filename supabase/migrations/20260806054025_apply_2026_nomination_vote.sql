-- Apply the church vote recorded in the approved 2026-2028 second-reading
-- nomination report. Only names marked with an asterisk in that report are
-- included here; the blank Church Board vacancy is intentionally excluded.

create temp table nomination_vote_targets (
  ord integer primary key,
  role_name text not null,
  person_name text not null,
  pdf_position text,
  term_end date
) on commit drop;

insert into nomination_vote_targets (
  ord,
  role_name,
  person_name,
  pdf_position,
  term_end
)
values
  (1, 'Adventist Community Services', 'Paul Daniel', 'Head', null),
  (2, 'Adventurer Club', 'Emma Lutz', 'Co-Leader', null),
  (3, 'Adventurer Club', 'Ilene Soltero', 'Co-Leader', null),
  (4, 'Building Operations & Maintenance', 'Monte Engeberg', 'Co-Leader', null),
  (5, 'Building Operations & Maintenance', 'Patrick Faulconer', 'Co-Leader', null),
  (6, 'Baby & Bridal Events', 'Candice Todd', 'Leader', null),
  (7, 'Care & Nurture', 'Diane Berry', 'Leader', null),
  (8, 'Church Board', 'Phil Van Lanen', 'Head Elder', null),
  (9, 'Church Board', 'Lowell Cooper', 'Assistant Chair', null),
  (10, 'Church Board', 'Monte Engeberg', 'Head Deacon', null),
  (11, 'Church Board', 'Tammy Stewart', 'Clerk, Head Deaconess', null),
  (12, 'Church Board', 'Lisa Ortiz', 'Welcome', null),
  (13, 'Church Board', 'Larry Swisher', 'Elder', null),
  (14, 'Church Board', 'Victoria Lahti', 'Discipleship', null),
  (15, 'Church Board', 'Stephen Canaday', 'Treasurer', null),
  (16, 'Church Board', 'Micheal Young', 'Pathfinder Leader', null),
  (17, 'Church Board', 'Patrick Faulconer', 'Operations', null),
  (18, 'Church Life Leader', 'Victoria Lahti', null, null),
  (19, 'Church Life Leader', 'Jason Wickersham', null, null),
  (20, 'Church Life Leader', 'Lisa Ortiz', null, null),
  (21, 'Church Life Leader', 'Bobby Jo Engeberg', null, null),
  (22, 'Deacon', 'Monte Engeberg', 'Head', null),
  (23, 'Deacon', 'Patrick Faulconer', 'Assistant', null),
  (24, 'Deacon', 'Fred Anderson', 'Assistant', null),
  (25, 'Deacon', 'Nathan Lull', 'Assistant', null),
  (26, 'Deaconess', 'Tammy Stewart', 'Head', null),
  (27, 'Design & Decor Team', 'Iwalani Fuller', 'Co-Leader', null),
  (28, 'Design & Decor Team', 'Randie Fuller', 'Co-Leader', null),
  (29, 'Diaper Bank', 'Marlene Schweighardt', 'Head', null),
  (30, 'Diaper Bank Board', 'Marlene Schweighardt', 'Board Member', null),
  (31, 'Diaper Bank Board', 'Stanley Arlt', 'Board Member', null),
  (32, 'Diaper Bank Board', 'Paula Stegman', 'Board Member', null),
  (33, 'Elder', 'Phil Van Lanen', 'Head', null),
  (34, 'Elder', 'Lowell Cooper', 'Elder', null),
  (35, 'Elder', 'Lisa Ortiz', 'Elder', null),
  (36, 'Elder', 'Larry Swisher', 'Elder', null),
  (37, 'Elder', 'Marilyn Montenegro', 'Elder', null),
  (38, 'Elder', 'Enio Montenegro', 'Elder', null),
  (39, 'Elder', 'Victoria Lahti', 'Elder', null),
  (40, 'Finance Committee', 'Lowell Cooper', 'Chair', null),
  (41, 'Finance Committee', 'Tammy Stewart', 'Head Deaconess', null),
  (42, 'Finance Committee', 'Phil Van Lanen', 'Head Elder', null),
  (43, 'Finance Committee', 'Monte Engeberg', 'Head Deacon', null),
  (44, 'Finance Committee', 'Stephen Canaday', 'Treasurer', null),
  (45, 'Finance Committee', 'Jason Worf', 'Ex officio member', null),
  (46, 'Health Ministry Team', 'Rae Cooper', 'Head', null),
  (47, 'Health Ministry Team', 'Valarie Young', 'Assistant', null),
  (48, 'Women''s Ministry', 'Rae Cooper', 'Head', null),
  (49, 'Women''s Ministry', 'Valarie Young', 'Assistant', null),
  (50, 'Hospitality Team', 'Pamela Olson', 'Head', null),
  (51, 'Library', 'Corrie Sample', 'Leader', null),
  (52, 'Men''s Ministry', 'Trevin Roletto', 'Head', null),
  (53, 'Pathfinder Club', 'Monte Engeberg', 'Co-Leader', null),
  (54, 'Pathfinder Club', 'Micheal Young', 'Co-Leader', null),
  (55, 'Prayer Ministry', 'Paula Stegman', 'Head', null),
  (56, 'Sabbath School — Fireside D', 'John Henriques', 'Teacher', null),
  (57, 'Sabbath School — Event Center', 'Patrick Faulconer', 'Leader', null),
  (58, 'Sabbath School — Event Center', 'Victoria Lahti', 'Teacher', null),
  (59, 'Sabbath School — Fireside C', 'Fred Anderson', 'Teacher', null),
  (60, 'Sabbath School — Fireside C', 'Kristy Baker', 'Teacher', null),
  (61, 'Sabbath School — Sanctuary', 'Lowell Cooper', 'Leader', null),
  (62, 'Sabbath School — Sanctuary', 'Phil Van Lanen', 'Teacher', null),
  (63, 'Sabbath School — Spanish', 'Enio Montenegro', 'Co-Leader', null),
  (64, 'Sabbath School — Spanish', 'Marilyn Montenegro', 'Co-Leader', null),
  (65, 'Sabbath School — Beginners', 'Ilene Soltero', 'Leader', null),
  (66, 'Sabbath School — Beginners', 'Emma Lutz', 'Teacher', null),
  (67, 'Sabbath School — Beginners', 'Tiana Waterbrook', 'Teacher', null),
  (68, 'Sabbath School — Kindergarten', 'Hazel Burns', 'Leader', null),
  (69, 'Sabbath School — Kindergarten', 'Kara Lull', 'Teacher', null),
  (70, 'Sabbath School — Primary', 'Sarah Faulconer', 'Co-Leader', null),
  (71, 'Sabbath School — Primary', 'Vaughn MacKenzie', 'Co-Leader', null),
  (72, 'Sabbath School — Primary', 'Margaret McNeill', 'Teacher', null),
  (73, 'Sabbath School — Primary', 'Mayra Soltero', 'Teacher', null),
  (74, 'Sabbath School — Junior', 'Randie Fuller', 'Co-Leader', null),
  (75, 'Sabbath School — Junior', 'Iwalani Fuller', 'Co-Leader', null),
  (76, 'Sabbath School — Teen', 'Jill Maldonado', 'Co-Leader', null),
  (77, 'Sabbath School — Teen', 'Rae Cooper', 'Co-Leader', null),
  (78, 'Sabbath School — Teen', 'Sirrel Maldonado', 'Teacher', null),
  (79, 'Sabbath School Secretary', 'Paula Stegman', 'Head', null),
  (80, 'Sabbath School Secretary', 'Diane Berry', 'Assistant', null),
  (81, 'Sabbath School Secretary', 'Cathy Marsh', 'Assistant', null),
  (82, 'Sabbath School Secretary', 'Emma Lutz', 'Assistant', null),
  (83, 'Social Events Committee', 'Kathryn Holm', 'Head', null),
  (84, 'Spanish Translation', 'Petra Flores', 'Head', null),
  (85, 'Technology — Audio', 'Harvey Lighthouse', 'Head', null),
  (86, 'Technology — Live Stream', 'Michael Urie', 'Head', null),
  (87, 'Technology — Multimedia', 'Michael Urie', 'Head', null),
  (88, 'Treasurer', 'Stephen Canaday', 'Head', null),
  (89, 'Treasurer', 'Harvey Lighthouse', 'Assistant', null),
  (90, 'Treasurer', 'Dalet Mendoza', 'Assistant', null),
  (91, 'Tri City Adventist School Board', 'Nathan Lull', '26-28 Term', '2028-06-30'),
  (92, 'Tri City Adventist School Board', 'Tiana Waterbrook', '26-28 Term', '2028-06-30'),
  (93, 'Welcome Team', 'Lisa Ortiz', 'Head', null);

-- Some older imports did not carry a position into committee and board
-- assignments. Add only the official starred positions needed by this vote.
with positions_to_add as (
  select distinct
    r.id as role_id,
    t.pdf_position as name,
    case
      when lower(t.pdf_position) like 'head%' then 10
      when lower(t.pdf_position) in ('chair', 'assistant chair') then 20
      when lower(t.pdf_position) like '%leader%' then 30
      when lower(t.pdf_position) like 'assistant%' then 40
      else 100
    end::smallint as leadership_rank
  from nomination_vote_targets t
  join public.roles r on r.name = t.role_name
  where t.pdf_position is not null
    and t.role_name <> 'Tri City Adventist School Board'
    and (
      t.role_name = 'Church Board'
      or exists (
        select 1
        from public.assignments a
        join public.people p on p.id = a.person_id
        left join public.terms tm on tm.id = a.term_id
        where a.role_id = r.id
          and concat_ws(
            ' ',
            coalesce(nullif(p.preferred_name, ''), p.first_name),
            p.last_name
          ) = t.person_name
          and a.status = 'active'
          and a.archived_at is null
          and a.sub_role_id is null
          and (t.term_end is null or tm.end_date = t.term_end)
      )
    )
)
insert into public.sub_roles (
  role_id,
  name,
  leadership_rank,
  is_active,
  requires_vote
)
select role_id, name, leadership_rank, true, true
from positions_to_add
on conflict do nothing;

with positions_to_update as (
  select distinct
    r.id as role_id,
    t.pdf_position as name,
    case
      when lower(t.pdf_position) like 'head%' then 10
      when lower(t.pdf_position) in ('chair', 'assistant chair') then 20
      when lower(t.pdf_position) like '%leader%' then 30
      when lower(t.pdf_position) like 'assistant%' then 40
      else 100
    end::smallint as leadership_rank
  from nomination_vote_targets t
  join public.roles r on r.name = t.role_name
  where t.pdf_position is not null
    and t.role_name <> 'Tri City Adventist School Board'
    and (
      t.role_name = 'Church Board'
      or exists (
        select 1
        from public.assignments a
        join public.people p on p.id = a.person_id
        left join public.terms tm on tm.id = a.term_id
        where a.role_id = r.id
          and concat_ws(
            ' ',
            coalesce(nullif(p.preferred_name, ''), p.first_name),
            p.last_name
          ) = t.person_name
          and a.status = 'active'
          and a.archived_at is null
          and a.sub_role_id is null
          and (t.term_end is null or tm.end_date = t.term_end)
      )
    )
)
update public.sub_roles sr
set requires_vote = true,
    is_active = true,
    leadership_rank = ptu.leadership_rank,
    updated_at = now()
from positions_to_update ptu
where sr.role_id = ptu.role_id
  and lower(btrim(sr.name)) = lower(btrim(ptu.name));

-- Attach newly defined positions to existing starred assignments that lacked
-- one. The school-board text describes a term rather than a position, so it
-- deliberately remains governed by the ministry-level vote setting.
update public.assignments a
set sub_role_id = sr.id,
    updated_at = now()
from nomination_vote_targets t
join public.roles r on r.name = t.role_name
join public.people p
  on concat_ws(
    ' ',
    coalesce(nullif(p.preferred_name, ''), p.first_name),
    p.last_name
  ) = t.person_name
join public.sub_roles sr
  on sr.role_id = r.id
 and lower(btrim(sr.name)) = lower(btrim(t.pdf_position))
left join public.terms tm on tm.end_date = t.term_end
where a.person_id = p.id
  and a.role_id = r.id
  and a.status = 'active'
  and a.archived_at is null
  and a.sub_role_id is null
  and t.pdf_position is not null
  and t.role_name <> 'Tri City Adventist School Board'
  and (t.term_end is null or a.term_id = tm.id);

-- Four named Church Board assignments were in the approved report but absent
-- from the imported assignment table. Insert them using the same 2026-2028
-- fiscal term as the other current Church Board members.
insert into public.assignments (
  person_id,
  role_id,
  sub_role_id,
  term_id,
  vote_date,
  status,
  is_public
)
select
  p.id,
  r.id,
  sr.id,
  tm.id,
  '2026-06-27'::date,
  'active',
  true
from nomination_vote_targets t
join public.roles r on r.name = t.role_name
join public.people p
  on concat_ws(
    ' ',
    coalesce(nullif(p.preferred_name, ''), p.first_name),
    p.last_name
  ) = t.person_name
join public.sub_roles sr
  on sr.role_id = r.id
 and lower(btrim(sr.name)) = lower(btrim(t.pdf_position))
join public.terms tm
  on tm.start_date = '2026-07-01'
 and tm.end_date = '2028-06-30'
where t.role_name = 'Church Board'
  and not exists (
    select 1
    from public.assignments existing
    where existing.person_id = p.id
      and existing.role_id = r.id
      and existing.status = 'active'
      and existing.archived_at is null
      and existing.term_id = tm.id
  );

-- Record the date on each matching starred assignment. Combined headings in
-- the source document intentionally map to both corresponding app ministries:
-- Diaper Bank plus its Board, Health plus Women's Ministry, and Live Stream
-- plus Multimedia.
update public.assignments a
set vote_date = '2026-06-27'::date,
    updated_at = now()
from nomination_vote_targets t
join public.roles r on r.name = t.role_name
join public.people p
  on concat_ws(
    ' ',
    coalesce(nullif(p.preferred_name, ''), p.first_name),
    p.last_name
  ) = t.person_name
left join public.terms tm on tm.end_date = t.term_end
where a.person_id = p.id
  and a.role_id = r.id
  and a.status = 'active'
  and a.archived_at is null
  and (t.term_end is null or a.term_id = tm.id);

-- Prefer ministry-specific position rules. This leaves unstarred people alone
-- even when they serve in the same ministry as a starred person.
update public.sub_roles sr
set requires_vote = true,
    updated_at = now()
where exists (
  select 1
  from nomination_vote_targets t
  join public.roles r on r.name = t.role_name
  join public.people p
    on concat_ws(
      ' ',
      coalesce(nullif(p.preferred_name, ''), p.first_name),
      p.last_name
    ) = t.person_name
  join public.assignments a
    on a.person_id = p.id
   and a.role_id = r.id
   and a.sub_role_id = sr.id
   and a.status = 'active'
   and a.archived_at is null
  left join public.terms tm on tm.id = a.term_id
  where t.term_end is null or tm.end_date = t.term_end
);

-- Only ministries whose starred assignments legitimately have no position use
-- the ministry-level rule. At present that is Church Life Leader and the
-- already-vote-governed Tri City Adventist School Board.
update public.roles r
set requires_vote = true,
    updated_at = now()
where exists (
  select 1
  from nomination_vote_targets t
  join public.people p
    on concat_ws(
      ' ',
      coalesce(nullif(p.preferred_name, ''), p.first_name),
      p.last_name
    ) = t.person_name
  join public.assignments a
    on a.person_id = p.id
   and a.role_id = r.id
   and a.status = 'active'
   and a.archived_at is null
  left join public.terms tm on tm.id = a.term_id
  where t.role_name = r.name
    and a.sub_role_id is null
    and (t.term_end is null or tm.end_date = t.term_end)
);

do $$
declare
  matched_count integer;
  ready_count integer;
begin
  -- A clean development database has no imported church roster. The historical
  -- vote reconciliation is a no-op there; populated databases retain the strict
  -- 93-assignment checks below.
  if not exists (select 1 from public.people) then
    return;
  end if;
  select count(*)
  into matched_count
  from nomination_vote_targets t
  join public.roles r on r.name = t.role_name
  join public.people p
    on concat_ws(
      ' ',
      coalesce(nullif(p.preferred_name, ''), p.first_name),
      p.last_name
    ) = t.person_name
  join public.assignments a
    on a.person_id = p.id
   and a.role_id = r.id
   and a.status = 'active'
   and a.archived_at is null
  left join public.terms tm on tm.id = a.term_id
  where t.term_end is null or tm.end_date = t.term_end;

  if matched_count <> 93 then
    raise exception
      'Expected 93 app assignment mappings for 89 named vote records; found %.',
      matched_count;
  end if;

  select count(*)
  into ready_count
  from nomination_vote_targets t
  join public.roles r on r.name = t.role_name
  join public.people p
    on concat_ws(
      ' ',
      coalesce(nullif(p.preferred_name, ''), p.first_name),
      p.last_name
    ) = t.person_name
  join public.assignments a
    on a.person_id = p.id
   and a.role_id = r.id
   and a.status = 'active'
   and a.archived_at is null
  left join public.sub_roles sr on sr.id = a.sub_role_id
  left join public.terms tm on tm.id = a.term_id
  where (t.term_end is null or tm.end_date = t.term_end)
    and a.vote_date = '2026-06-27'::date
    and (r.requires_vote or coalesce(sr.requires_vote, false));

  if ready_count <> 93 then
    raise exception
      'Expected all 93 mapped assignments to have the vote rule and date; found %.',
      ready_count;
  end if;
end;
$$;

notify pgrst, 'reload schema';
