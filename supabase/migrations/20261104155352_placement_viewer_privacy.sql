-- Recruitment responses and contact notes are private to administrators/editors.
-- Keep applied migrations immutable; tighten the existing policies forward.
alter policy placement_candidates_read on public.placement_candidates
  to authenticated
  using (private.has_church_role(church_id,array['admin','editor']));
alter policy volunteer_history_read on public.volunteer_contact_history
  to authenticated
  using (private.has_church_role(church_id,array['admin','editor']));
comment on policy placement_candidates_read on public.placement_candidates is
  'Active church administrators and editors may read recruitment candidates; viewers may not.';
comment on policy volunteer_history_read on public.volunteer_contact_history is
  'Active church administrators and editors may read volunteer call history; viewers may not.';
