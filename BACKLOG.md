# App follow-up work

## Invitation email wording and delivery flow

Requested by Jason on November 3, 2026. Status: **To do**.

Jason clarified that the first screenshot was a separate password-reset email. The corrected invitation screenshot has the subject/heading “You’ve been invited” and generic copy: “You’ve been invited to create an account. Follow the link below to accept.” Replace that generic invitation with the app-specific welcome and password-setup instructions below. Do not treat the separate password-reset screenshot as an invitation bug.

Suggested Riverview copy:

**Subject:** You’ve been invited to Riverview Ministry Volunteers App

You’ve been invited to Riverview Ministry Volunteers App. To get started, click the link below and enter a new password for your account.

**[Set Up Your Account]**

You’re receiving this email because an admin in your Ministry Volunteers team has invited you.

Thanks,

Riverview Ministry Volunteers App

### Implementation and acceptance

- Review both first invitations and invitation resends in `supabase/functions/admin-users/index.ts`. The resend path currently calls `resetPasswordForEmail`; first invitations call `inviteUserByEmail`.
- Make invitation and resend emails use invitation wording and a working account/password setup link. Keep genuine password-reset messages appropriate to password recovery.
- Use the inviting church’s name for other churches; the copy above is the Riverview example.
- Verify subject, sender display name, body, button, mobile appearance, link expiry, and successful password setup for both first invitation and resend.
- Send test emails only to an authorized test recipient. Do not re-invite existing church users as a test.

This is a follow-up task; the email behavior has not been changed as part of the placement workflow implementation.
