# Native placement and Focus cards

Version 1.3 build 20 brings the web workflow's card presentation to the native app:

- Selectable opening cards expand to recruitment controls and candidate cards. Candidate cards show phone/email links and current positions, and open the calling/approval workspace.
- Searchable selection sheets provide full lists and type-to-filter controls for ministries, positions, terms, candidates, and callers. Opening creation supports inline ministry, position, and term creation, without a fixed headcount. Duplicate warnings, explicit Finish Recruiting, Trash, and Restore use the existing checked workflow commands.
- Focus shows five attention-colored cards. Sections expand into the workspace and collapse through the heading or Close. Needing Votes routes to the existing Votes tab. Activation uses the same newest-100 Planning Center selection and church membership preferences as the web app; admins can change membership types in Focus or Planning Center settings.
- Needing Votes uses cards for nominations and existing placements, with collapsible Bulletin Suggestions. First-reading publication remains a checkbox. Recording the vote completes second reading. The Record Vote button occupies a compact, single-line row rather than competing with the date field.
- Viewers do not receive the Placement tab or person call-history sections. The separate forward migration restricts candidate and call-history reads to church admins/editors at the database level. Previously applied migrations remain unchanged.

Validation: 23 native tests on the macOS target, including shared Focus API/settings and phone-width rendering checks; rendered Focus/opening cards and vote action visually inspected; signed iOS archive. These renders check SwiftUI layout at narrow widths and do not replace physical iPhone/iPad review. Public App Store release stays withdrawn; this build is for internal TestFlight testing.
