---
name: tapauth
description: >-
  Use when you need delegated access from a user: OAuth tokens for Google Calendar, Gmail, GitHub,
  Slack, Linear, Notion, Vercel, Sentry, Asana, Discord, Apify, or Jira; or a user-entered password
  or fixed API key via the `secret` provider. Just run the bundled script and it handles grant
  creation, user approval, token/secret caching, and OAuth refresh when available. Do NOT use when
  you already have direct credentials.
license: MIT
compatibility: Requires curl and bash. Works with Claude Code, Cursor, OpenClaw, Codex, GitHub Copilot, and any agent with shell access.
metadata:
  author: tapauth
  version: "1.0"
  website: https://tapauth.ai
  docs: https://tapauth.ai/docs
---

# TapAuth — Delegated Access for AI Agents

TapAuth lets your agent ask users for delegated access without hardcoding credentials.
The user approves OAuth access or shares a requested password/API key in their browser. You retrieve the approved token or secret through the grant.

## How It Works

This skill includes a CLI script at `scripts/tapauth.sh` with two modes:

### Step 1 — Get the approval URL (default mode)

```bash
scripts/tapauth.sh google calendar.readonly
```

This creates a grant and prints the approval URL to stdout:
```
Approve access: https://tapauth.ai/approve/abc123

Show this URL to the user, then start --token immediately; it waits until approval completes.
```

**Show the URL to the user.** They must click it, sign in, and approve. This command exits immediately — it does not block or poll.

### Step 2 — Immediately run the API call with `--token`

```bash
curl -H "Authorization: Bearer $(scripts/tapauth.sh --token google calendar.readonly)" \
  "https://www.googleapis.com/calendar/v3/calendars/primary/events"
```

Run this **right after** showing the URL — do not wait for the user to confirm they approved, and do not end the turn after sending the link. The `--token` flag is the polling step: it waits automatically (every 5 seconds, up to 10 minutes) until the user approves, then outputs the bearer token or shared secret to stdout. The `$(...)` substitution feeds it directly into curl.

If the API operation may run longer than the foreground execution limit, start the same polling/API command as a tracked background process and inspect its output when it completes. The important rule is unchanged: after showing the approval URL, immediately start the real API operation with inline `$(scripts/tapauth.sh --token <provider> <scopes>)`.

**Always use `--token` inline with `$(...)`.** Do NOT capture the token into a shell variable like `TOKEN=$(...)`. The inline pattern keeps the token out of shell history and process listings.

**On subsequent runs,** the cached grant is reused. Default mode prints "Already authorized", and `--token` fetches a fresh bearer token immediately.

> **⚠️ IMPORTANT: Always run default mode first on first use with a provider.**
>
> Do NOT skip straight to `--token` inside `$(...)` on first run.
> If there is no cached approved grant yet, `--token` exits and tells you to run
> default mode first so the approval URL can be shown to the user.

## Gotchas

- **No TapAuth API key needed.** TapAuth is zero-config. Do not look for TapAuth API keys, client secrets, or environment variables. Just run the script.
- **Always use the bundled script.** The script is at `scripts/tapauth.sh` inside this skill. Do NOT download it from the website — you already have it.
- **Always run default mode first, then immediately start the real API command with `--token`.** Default mode prints the approval URL to stdout and exits. `--token` mode polls and returns the bearer token. Don't skip to `--token` on first run, and don't stop after showing the approval URL — the user approves while `--token` is already polling.
- **Scopes are provider-specific.** Some providers need them (Google, GitHub, Linear, Slack), Vercel uses a compatibility default, and Notion uses integration-level permissions. See the Quick Reference table below. Check the provider's reference file (e.g. `references/google.md`) for valid scope values.
- **Plan scopes for the whole workflow.** If a task needs discovery plus mutation, request both scopes up front. Example: adding events to a Google Calendar by name requires calendar-list read access to find the calendar ID plus event write access to insert the event.
- **Manual secrets use `secret`.** Run `scripts/tapauth.sh secret "<description>" "[validation_regex]" "[validation_hint]"` when the user must provide a password or fixed API key. The description is part of the local lookup key, so make it short, unique, stable, and human-readable, such as `Stripe Secret Key` or `Production Database Password`. Put format instructions in `validation_hint`, not in the description. The approval page encrypts the value in the browser before sending it to TapAuth.
- **Validation regex is a UX guard.** The browser checks it before encrypting, but the agent should still validate the retrieved secret because the server intentionally cannot inspect the plaintext.
- **Manual secret expiry is TapAuth-side only.** Expiry stops TapAuth from returning the secret; it does not rotate, revoke, or invalidate the underlying password/API key.
- **Approved grants are cached automatically.** After the first approval, default mode detects existing authorization and `--token` can fetch a fresh token immediately. Don't create a new grant when you already have a working cached grant.
- **Multiple scopes:** Pass comma-separated: `scripts/tapauth.sh google calendar.events,spreadsheets`
- **OpenClaw agents:** If running under OpenClaw, prefer the exec secrets provider (`references/openclaw.md`) over inline `$(...)` — it resolves tokens at startup and keeps them out of shell commands entirely.

## Quick Reference — Provider + Scopes

Most providers require scopes. Some (Vercel, Notion) use integration-level permissions instead. Here's the cheat sheet:

| Provider | Command | Scopes |
|----------|---------|--------|
| Google Calendar (read) | `scripts/tapauth.sh google calendar.readonly` | See `references/google.md` |
| Google Calendar (events by known ID) | `scripts/tapauth.sh google calendar.events` | Create/edit/delete events when the calendar ID is already known |
| Google Calendar (add by name) | `scripts/tapauth.sh google calendar.events,calendar.calendarlist.readonly` | List calendars by name, then create/edit/delete events |
| Google Calendar (full) | `scripts/tapauth.sh google calendar` | Full Calendar access when narrower scopes do not cover the workflow |
| Google Drive | `scripts/tapauth.sh google drive.readonly` | See `references/google.md` |
| Google Sheets | `scripts/tapauth.sh google spreadsheets.readonly` | Use `google` provider with sheets scopes |
| Google Docs | `scripts/tapauth.sh google documents.readonly` | Use `google` provider with docs scopes |
| GitHub | `scripts/tapauth.sh github repo` | `repo`, `read:user`, etc. |
| Vercel | `scripts/tapauth.sh vercel` | Integration-level; script defaults to `project` for API validation |
| Notion | `scripts/tapauth.sh notion` | Integration-level (no per-grant scopes) |
| Slack | `scripts/tapauth.sh slack users:read` | `users:read`, `channels:read`, etc. |
| Asana | `scripts/tapauth.sh asana tasks:read` | `tasks:read`, `projects:read`, etc. |
| Linear | `scripts/tapauth.sh linear read` | `read`, `write`, `issues:create` |
| Sentry | `scripts/tapauth.sh sentry project:read` | `org:read`, `project:read`, etc. |
| Discord | `scripts/tapauth.sh discord identify` | `identify`, `guilds`, etc. |
| Apify | `scripts/tapauth.sh apify full_api_access` | `full_api_access` |
| Jira | `scripts/tapauth.sh atlassian read:jira-work` | `read:jira-work`, `write:jira-work`, etc. |
| Manual Secret | `scripts/tapauth.sh secret "Stripe Secret Key" "^sk_" "Use a Stripe secret key that starts with sk_"` | No scopes |

**Key rule:** For OAuth providers, always specify the scopes you need. For manual secrets, always provide a short, unique, stable, human-readable description because it is used as a lookup key. `validation_regex` and `validation_hint` are optional; the hint is shown only if the regex check fails.

## Usage Pattern

The pattern is always the same — **default mode first, then `--token`:**

```bash
# 1. Get the approval URL (show it to the user)
scripts/tapauth.sh <provider> [scopes]

# 2. Use the token
curl -H "Authorization: Bearer $(scripts/tapauth.sh --token <provider> [scopes])" \
  <api-url>
```

For a user-entered password or fixed API key:

```bash
# 1. Ask the user for a specific secret
scripts/tapauth.sh secret "Stripe Secret Key" "^sk_" "Use a Stripe secret key that starts with sk_"

# 2. Use it after approval
curl -H "Authorization: Bearer $(scripts/tapauth.sh --token secret "Stripe Secret Key" "^sk_" "Use a Stripe secret key that starts with sk_")" \
  https://api.stripe.com/v1/customers
```

For requests that need a body:

```bash
curl -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh --token <provider> <scopes>)" \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}' \
  <api-url>
```

For multiple requests, repeat the `$(...)` inline pattern — the cached grant is reused so each call returns immediately after fetching a fresh token:

```bash
curl -H "Authorization: Bearer $(scripts/tapauth.sh --token github repo)" \
  "https://api.github.com/repos/owner/repo/issues?state=open&per_page=10"

curl -X POST -H "Authorization: Bearer $(scripts/tapauth.sh --token github repo)" \
  -H "Content-Type: application/json" \
  -d '{"title": "Bug report", "body": "Details here"}' \
  "https://api.github.com/repos/owner/repo/issues"
```

Do NOT store the token in a shell variable — the inline `$(...)` pattern is both simpler and more secure.

## First-Run Flow

On first use with a provider:

1. Run `scripts/tapauth.sh <provider> [scopes]` (default mode) — creates a grant, prints the approval URL, exits immediately.
2. **Show the approval URL to the user.**
3. Immediately run your real API operation with `$(scripts/tapauth.sh --token <provider> [scopes])` — this is the polling step. It waits automatically until the user approves, then returns the bearer token or shared secret.
4. Do not end the turn while waiting for approval. If foreground execution may time out, run the polling/API command as a tracked background process and inspect the result when it completes.

Example default-mode output:
```
Approve access: https://tapauth.ai/approve/abc123

Show this URL to the user, then start --token immediately; it waits until approval completes.
```

Example `--token` mode (polling):
```
Waiting for approval... (2s)
Waiting for approval... (4s)
```

Once approved, the grant is cached. Subsequent runs of either mode return immediately.

## Real-World Examples

### List Google Calendar events

```bash
curl -s -H "Authorization: Bearer $(scripts/tapauth.sh --token google calendar.readonly)" \
  "https://www.googleapis.com/calendar/v3/calendars/primary/events?maxResults=10&orderBy=startTime&singleEvents=true&timeMin=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

### Create a Google Calendar event

```bash
# Replace YYYY-MM-DD with a future date (e.g. 2025-06-15)
curl -s -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh --token google calendar.events)" \
  -H "Content-Type: application/json" \
  -d '{
    "summary": "Team standup",
    "start": {"dateTime": "YYYY-MM-DDT09:00:00Z"},
    "end":   {"dateTime": "YYYY-MM-DDT09:30:00Z"}
  }' \
  "https://www.googleapis.com/calendar/v3/calendars/primary/events"
```

### Create a Google Calendar event by calendar name

Use both scopes because `calendar.events` can create events but cannot list calendars by name:

```bash
CALENDAR_ID="$(curl -s -H "Authorization: Bearer $(scripts/tapauth.sh --token google calendar.events,calendar.calendarlist.readonly)" \
  "https://www.googleapis.com/calendar/v3/users/me/calendarList" \
  | jq -r '.items[] | select(.summary == "Charlie & Sam") | .id' | head -n 1)"
test -n "$CALENDAR_ID" || { echo "Calendar not found: Charlie & Sam" >&2; exit 1; }

curl -s -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh --token google calendar.events,calendar.calendarlist.readonly)" \
  -H "Content-Type: application/json" \
  -d '{
    "summary": "Team standup",
    "start": {"dateTime": "YYYY-MM-DDT09:00:00Z"},
    "end":   {"dateTime": "YYYY-MM-DDT09:30:00Z"}
  }' \
  "https://www.googleapis.com/calendar/v3/calendars/${CALENDAR_ID}/events"
```

### Read a GitHub repo's issues

```bash
curl -s -H "Authorization: Bearer $(scripts/tapauth.sh --token github repo)" \
  "https://api.github.com/repos/owner/repo/issues?state=open&per_page=10"
```

### Create a GitHub issue

```bash
curl -s -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh --token github repo)" \
  -H "Content-Type: application/json" \
  -d '{"title": "Fix login bug", "body": "Steps to reproduce..."}' \
  "https://api.github.com/repos/owner/repo/issues"
```

### Send an email via Gmail

```bash
# Base64-encode the email
EMAIL=$(printf "To: recipient@example.com\r\nSubject: Hello\r\n\r\nMessage body" | base64)

curl -s -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh --token google https://www.googleapis.com/auth/gmail.send)" \
  -H "Content-Type: application/json" \
  -d "{\"raw\": \"$EMAIL\"}" \
  "https://www.googleapis.com/gmail/v1/users/me/messages/send"
```

### Query Linear issues

```bash
curl -s -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh --token linear read)" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ issues(first: 10) { nodes { title state { name } } } }"}' \
  "https://api.linear.app/graphql"
```

### Search Notion

```bash
curl -s -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh --token notion)" \
  -H "Content-Type: application/json" \
  -H "Notion-Version: 2022-06-28" \
  -d '{"query": "meeting notes"}' \
  "https://api.notion.com/v1/search"
```

### List Google Drive files

```bash
curl -s -H "Authorization: Bearer $(scripts/tapauth.sh --token google drive.readonly)" \
  "https://www.googleapis.com/drive/v3/files?pageSize=10&fields=files(id,name,mimeType)"
```

### List Vercel deployments

```bash
curl -s -H "Authorization: Bearer $(scripts/tapauth.sh --token vercel)" \
  "https://api.vercel.com/v6/deployments?limit=5"
```

## Configuration

**Environment variables:**
- `TAPAUTH_BASE_URL` — Override the base URL (default: `https://tapauth.ai`)
- `TAPAUTH_HOME` — Override the cache directory (takes highest priority)
- `CLAUDE_PLUGIN_DATA` — Stable per-plugin directory provided by Claude Code (used automatically if set)

**Cache directory priority:** `TAPAUTH_HOME` > `CLAUDE_PLUGIN_DATA` > `./.tapauth`

**Caching:** Grant credentials are stored in the cache directory (mode 700, files mode 600). Each provider+scope combination gets its own cache file with the grant ID and grant secret. Bearer tokens are fetched on demand and are not written to disk.

## Supported Providers

See `references/` for provider-specific scopes, examples, and API details:

| Provider | ID | Scopes Reference |
|----------|----|------------------|
| GitHub | `github` | `references/github.md` |
| Google (multi-service) | `google` | `references/google.md` |
| Gmail | `google` with gmail scopes | `references/gmail.md` |
| Linear | `linear` | `references/linear.md` |
| Vercel | `vercel` | `references/vercel.md` |
| Notion | `notion` | `references/notion.md` |
| Slack | `slack` | `references/slack.md` |
| Sentry | `sentry` | `references/sentry.md` |
| Asana | `asana` | `references/asana.md` |
| Discord | `discord` | `references/discord.md` |
| Apify | `apify` | `references/apify.md` |
| Jira (Atlassian) | `atlassian` | `references/atlassian.md` |

> The `google` provider covers all Google services (Drive, Calendar, Sheets, Docs, Gmail, Contacts).

To list all providers and valid scopes programmatically:

```bash
curl -s https://tapauth.ai/api/v1/providers
```

## Provider Notes

- **GitHub:** The `repo` scope grants read/write to repositories. Use `read:user` for profile info only.
- **Google:** Supports automatic token refresh. Use the `google` provider for all Google services (Calendar, Sheets, Docs, Drive, Gmail, Contacts).
- **Notion/Vercel:** Scopes are fixed at integration level. Vercel does not need a scope in the command because the script supplies `project` for API validation.
- **Slack:** Uses `user_scope` permissions. Specify the scopes you need (e.g., `users:read`, `channels:read`).
- **Linear:** Requires explicit scopes (`read`, `write`, etc.).
- **Discord:** User OAuth tokens, not bot tokens. Tokens expire after ~7 days with automatic refresh.
- **Apify:** Uses Dynamic Client Registration (DCR) and PKCE. Only `full_api_access` scope available. Tokens expire and auto-refresh.
- **Jira (Atlassian):** Uses OAuth 2.0 (3LO) with PKCE. After getting a token, call the accessible-resources endpoint to get the cloud ID for API calls. Tokens expire in 1 hour with automatic refresh.

## Token Lifetimes & Revocation

TapAuth uses zero-knowledge encryption — tokens are encrypted with your `grant_secret`, which TapAuth never stores. This means:

- **TapAuth cannot revoke tokens at the provider level.** We literally cannot decrypt them.
- When a grant expires, the encrypted ciphertext is deleted without ever being read.
- Short-lived tokens (Google ~1hr, Linear ~1hr, Sentry ~8hr) expire naturally and auto-refresh.
- Long-lived tokens (GitHub, Slack, Vercel, Notion) must be revoked in provider settings if needed.

## Common Patterns

### Ask the user to approve, then proceed
```
1. Run scripts/tapauth.sh <provider> [scopes] — prints approval URL, exits immediately
2. Show the URL to the user
3. Immediately run curl with $(scripts/tapauth.sh --token <provider> [scopes]) — polls until approved
4. User approves in their browser while the script waits — curl executes automatically
```

### Handle expiry gracefully
If the cached grant is expired, re-run default mode to show the same approval URL again so the user can re-authorize and extend that grant. If the cached grant is revoked, denied, or deleted server-side, default mode creates a fresh approval URL automatically. `--token` will tell you which case applies; no manual cache deletion is required.

### Scope selection
Request the minimum scopes you need. Users see exactly what you're asking for and can approve with reduced permissions. Less scope = more trust = higher approval rate.

## The Raw API (Advanced)

If you can't use the CLI script, the API flow is:

1. **Create grant:** `POST https://tapauth.ai/api/v1/grants` with `provider` and `scopes`
2. **User approves** at the returned `approve_url`
3. **Get token:** `GET https://tapauth.ai/api/v1/grants/{grant_id}` with `Authorization: Bearer gs_...` header (add `Accept: text/plain` for .env format)

| Status | Meaning |
|--------|---------|
| 200 | Token ready |
| 202 | Pending — poll again in 2-5 seconds |
| 401 | Invalid grant_secret |
| 404 | Grant not found |
| 410 | Expired, revoked, or denied |

See the [API docs](https://tapauth.ai/docs) for full details on request/response formats.

## Common Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `tapauth: failed to create grant` | Invalid provider or scopes | Check `references/` for valid provider IDs and scope formats |
| `tapauth: cached grant expired` | Cached grant reached its expiry time | Run `scripts/tapauth.sh <provider> [scopes]` again to re-show the same approval URL, have the user re-authorize, then retry `--token` |
| `tapauth: cached grant is no longer usable` | Cached grant was revoked, denied, link-expired, or deleted server-side | Run `scripts/tapauth.sh <provider> [scopes]` again to create a fresh approval URL, then retry `--token` |
| Approval URL not visible | Skipped default mode and went straight to `--token` | Run `scripts/tapauth.sh <provider> [scopes]` (without `--token`) first to get the approval URL, show it to the user, then use `--token`. |
| `tapauth: timed out` | User didn't approve within 10 minutes | Re-run `scripts/tapauth.sh <provider> [scopes]`; it may reuse the same pending grant and approval URL. If you need a brand-new URL immediately, remove the cached grant file and run it again. |

## OpenClaw Secrets Provider

TapAuth integrates with OpenClaw's exec secrets provider. Configure one provider entry per grant — each runs `scripts/tapauth.sh --token` and returns a raw token or secret on stdout.

Example provider config (one entry per provider/scope combo):

```json
{
  "secrets": {
    "providers": {
      "tapauth_google": {
        "source": "exec",
        "command": "scripts/tapauth.sh",
        "args": ["--token", "google", "calendar.readonly"],
        "passEnv": ["HOME"],
        "jsonOnly": false
      }
    }
  }
}
```

Key points:
- **`command`** is a string path to `scripts/tapauth.sh` (resolved against the skill directory)
- **`args`** passes `--token`, the provider name, and scopes
- **`jsonOnly: false`** because the script outputs a raw token string, not JSON
- **`passEnv`** must include `HOME` so the script can find its token cache at `~/.tapauth/`
- Grants must be created and approved first — run `scripts/tapauth.sh <provider> <scopes>` (without `--token`) before configuring the exec provider

See `references/openclaw.md` for multi-provider examples, SecretRef usage, token lifecycle, and troubleshooting.
