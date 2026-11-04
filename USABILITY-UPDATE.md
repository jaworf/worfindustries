# Placement and administration usability

The web placement workspace now supports setting up a church while recruiting volunteers.

- Ministry, position, volunteer, caller, and assignment selectors support typing to filter and an arrow to show all options. New ministries, positions, and terms can be created while creating an opening.
- Openings appear as selectable cards. Recruiting stays open until explicitly finished; there is no fixed headcount. Duplicate active openings are blocked. Canceled openings move to Trash and can be restored when no conflicting opening exists.
- Candidate cards show contact links and current positions. Expanding a card provides call assignment, follow-up date, actual caller, call date, response, notes, and history. Admins can assign calls and enter another caller's results; editors can record only their own calls. Acceptance, nomination, readings, vote, and appointment remain separate steps.
- Staff accounts have first name, last name, and phone fields. A unique, active contact with the same email in the same church supplies identity automatically. Ambiguous household emails are not merged. Unmatched accounts complete their details during invitation setup or the next sign-in.
- Focus shows five compact cards with attention indicators. Sections expand and close; Needing Votes opens the single voting page. Volunteer Activation uses the 100 newest eligible Planning Center contacts, excludes current volunteers, and supports church-specific membership filters under Integrations. Riverview defaults to Riverview Member. Membership options are retrieved from Planning Center.
- People assessment and service matching is collapsed by default and loads profiles only when opened.
- Reports and printed PDFs list Name, Position, Term End, and Notes, without a vote-date column. Public-note restrictions remain in effect.

## Validation

91 backend/component regression tests, 18 rendered-route tests, 45 placement workflow/database checks, the existing account and church SQL checks, TypeScript, lint (warnings only), and the production build pass. Browser checks cover searchable controls, inline creation, duplicate warnings, Trash/restore, calls, editor restrictions, invitation setup, Focus, opt-in matching, desktop/mobile layouts, and a printed report using fictional records. The printed PDF was rendered and visually inspected.

This update changes the web app and shared backend. It does not contain a new native iOS build.
