# Teamify Email Notifications

Teamify sends transactional email through **one centralized sender identity**.
There are no per-event mailboxes (invitations, tasks, OTP, etc. all use the
same From name and address).

The application **cannot** create or verify a public domain or inbox for you.
A project owner must configure a transactional email provider, verify a domain
(or sender), and supply credentials via environment variables.

Until those values are set, in-app and Socket.IO notifications still work.
Emails are skipped and recorded as `skipped` (the UI shows **In-App Only**).
An email is shown as **Email Sent** only after the provider confirms submission.

## Provider

Default provider: **Resend**.

1. Create a Resend account.
2. Add and verify the Teamify domain (or a single sender address).
3. Create an API key.
4. Set the environment variables below.
5. Restart the Flask backend.

Do **not** hardcode keys or real addresses in source control.

## Required environment variables

Set these in the deployment environment (Render, Docker, systemd, etc.).
Placeholders also live in `teamify_flask_backend/.env.example`.

```
MAIL_PROVIDER=resend
RESEND_API_KEY=
MAIL_FROM_NAME=Teamify
MAIL_FROM_ADDRESS=
MAIL_APP_BASE_URL=
```

| Variable | Required | Purpose |
|---|---|---|
| `MAIL_PROVIDER` | no (defaults to `resend`) | Mail backend |
| `RESEND_API_KEY` | **yes** for real delivery | Resend API key |
| `MAIL_FROM_NAME` | no (defaults to `Teamify`) | Display name |
| `MAIL_FROM_ADDRESS` | **yes** for real delivery | Verified sender such as `no-reply@YOUR_DOMAIN` |
| `MAIL_APP_BASE_URL` | no | Public app origin used in CTA / preference links (no trailing slash) |

`.env` is gitignored. Never commit `RESEND_API_KEY`.

## Production setup

1. Verify `YOUR_DOMAIN` in the Resend dashboard (DNS records Resend provides).
2. Use a single sender, for example:
   - `Teamify <no-reply@YOUR_DOMAIN>`
   - `Teamify <notifications@YOUR_DOMAIN>`
3. Set `MAIL_FROM_NAME=Teamify` and `MAIL_FROM_ADDRESS=no-reply@YOUR_DOMAIN`.
4. Set `RESEND_API_KEY` to the production key.
5. Optionally set `MAIL_APP_BASE_URL` to the Flutter web / app origin so
   buttons can link to `/settings/email-notifications`.
6. Run database migrations so delivery tracking exists:

   ```
   cd teamify_flask_backend
   flask db upgrade
   ```

   `db.create_all()` also creates `email_deliveries` on boot if the table is missing.
7. Confirm the admin system setting **email_notifications** is enabled.
8. Restart the API process.

## What is emailed

| Event | Preference key | Notes |
|---|---|---|
| Project / team invitation | `emailTeamInvitations` | Also requires `masterEmailEnabled` |
| Invitation accepted | `emailInvitationResponses` | Sent to the project owner |
| Task assigned | `emailTaskAssignments` | |
| Task updated | `emailTaskUpdates` | Default **off** |
| Deadline reminder / overdue | `emailDeadlineReminders` | Deduped per task/action/day; respects `taskReminderTiming` |
| Chat DM / mention | `emailNewMessages` | Respects `messageEmailBehavior` |
| Role change | `emailRoleChanges` | |
| Removed from project | `emailMembershipChanges` | |
| Admin announcement | `emailAdminAnnouncements` | Deduped per user/content/day |
| Password reset OTP | *(always)* | Security email; ignores notification prefs. Never returned in the API. |

Platform switch: admin `email_notifications`. When false, **no notification
emails** are sent. OTP reset emails still attempt delivery because they are
account-recovery messages, not preference-driven notifications.

`deliveryFrequency`:
- `instant` — send immediately (background greenlet; does not block the API)
- `daily_digest` / `weekly_digest` — non-urgent types are skipped for now;
  invitations, assignments, and deadline emails still send immediately

## How to test a real email

1. Configure Resend with a **verified** `MAIL_FROM_ADDRESS` and `RESEND_API_KEY`.
2. Start the backend.
3. Use an account whose inbox you control.
4. Enable **Email Notifications** in admin settings and the user preference
   `masterEmailEnabled` plus the relevant category.
5. Trigger an event (forgot-password, invite a teammate, assign a task).
6. Confirm the message in Resend’s logs **and** the inbox.
7. Open `/api/notifications` and check `"email_delivered": true` only after
   Resend accepted the message (`id` returned).

Local automated tests mock Resend and never send mail.

## Limitations that still need a human

- Domain / sender verification in Resend (DNS).
- Choosing the real production domain and from-address.
- Creating the API key and storing it in the host’s secret store.
- Optional `MAIL_APP_BASE_URL` if you want working CTA links in emails.
- Digest-mode users do not yet receive a combined daily/weekly summary email.
