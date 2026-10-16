-- Reference seed for the original Riverview tenant only. Never apply these
-- ministry names or vote requirements to another church. No member data is seeded.
insert into public.terms (church_id, name, start_date, end_date, term_type)
select church.id, reference.*
from public.churches church
cross join (values
  ('July 2024 - June 2026', date '2024-07-01', date '2026-06-30', 'fiscal'),
  ('July 2025 - June 2027', date '2025-07-01', date '2027-06-30', 'fiscal'),
  ('Jan 26 - Dec 27', date '2026-01-01', date '2027-12-31', 'calendar'),
  ('July 26 - June 28', date '2026-07-01', date '2028-06-30', 'fiscal'),
  ('N/A', null, null, 'ongoing')
) as reference(name, start_date, end_date, term_type)
where church.slug = 'riverview'
on conflict do nothing;

insert into public.sub_roles (church_id, name, leadership_rank)
select church.id, reference.*
from public.churches church
cross join (values
  ('Head', 10),
  ('Leader', 10),
  ('Chairperson', 10),
  ('Co-Head', 20),
  ('Co-Leader', 20),
  ('Assistant Head', 30),
  ('Assistant', 40),
  ('Clerk', 50),
  ('Aid', 100),
  ('Backup', 100),
  ('Mentee', 100),
  ('Teacher', 100),
  ('Volunteer', 100)
) as reference(name, leadership_rank)
where church.slug = 'riverview'
on conflict do nothing;

insert into public.roles (church_id, name, display_order)
select church.id, reference.*
from public.churches church
cross join (values
  ('Adventist Community Services', 10),
  ('Adventurer Club', 20),
  ('Baby & Bridal Events', 30),
  ('Building Operations & Maintenance', 40),
  ('Care & Nurture', 50),
  ('Children''s Ministry', 60),
  ('Children''s Story Coordinator', 70),
  ('Church Board', 80),
  ('Church Life Leader', 90),
  ('Clerk', 100),
  ('Daily Bread Homeless Ministry', 110),
  ('Deacon', 120),
  ('Deaconess', 130),
  ('Design & Decor Team', 140),
  ('Diaper Bank', 150),
  ('Diaper Bank Board', 160),
  ('Digital Prayer Ministry', 170),
  ('Elder', 180),
  ('Evangelism & Outreach Team', 190),
  ('Finance Committee', 200),
  ('Health Ministry Team', 210),
  ('Hospitality Team', 220),
  ('Inactive Member Ministry', 230),
  ('Library', 240),
  ('Men''s Ministry', 250),
  ('Ministry Placement Committee', 260),
  ('Pathfinder Club', 270),
  ('Photographer', 280),
  ('Pianist & Organist Team', 290),
  ('Prayer Ministry', 300),
  ('Prison Ministry', 310),
  ('Sabbath School — Fireside D', 320),
  ('Sabbath School — Beginners', 330),
  ('Sabbath School — Event Center', 340),
  ('Sabbath School — Fireside C', 350),
  ('Sabbath School — Junior', 360),
  ('Sabbath School — Kindergarten', 370),
  ('Sabbath School — Primary', 380),
  ('Sabbath School — Sanctuary', 390),
  ('Sabbath School — Spanish', 400),
  ('Sabbath School — Teen', 410),
  ('Sabbath School — Young Adult', 420),
  ('Sabbath School Pianist', 430),
  ('Sabbath School Secretary', 440),
  ('Sabbath School Superintendent', 450),
  ('Sign Language Interpreter', 460),
  ('Social Events Committee', 470),
  ('Spanish Translation', 480),
  ('Special Meals & Events Team', 490),
  ('Special Music Coordinator', 500),
  ('Technology — Audio', 510),
  ('Technology — Live Stream', 520),
  ('Technology — Multimedia', 530),
  ('Technology — Network Management', 540),
  ('Treasurer', 550),
  ('Tri City Adventist School Board', 560),
  ('Volunteer Screening Coordinator', 570),
  ('Welcome Team', 580),
  ('Women''s Ministry', 590),
  ('Worship Committee', 600),
  ('Worship Leader', 610),
  ('Youth Activities Leader', 620),
  ('Youth and Young Adult Ministry', 630)
) as reference(name, display_order)
where church.slug = 'riverview'
on conflict do nothing;

-- These are the roles with recorded church vote dates in the supplied
-- assignment export. Other roles can be marked as vote-required in the app.
update public.roles
set requires_vote = true
where church_id = (select id from public.churches where slug = 'riverview')
  and name in (
  'Diaper Bank Board',
  'Ministry Placement Committee',
  'Tri City Adventist School Board'
);
