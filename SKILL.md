---
name: tapauth
description: >-
  Use when you need an OAuth token for a user's account — Google Calendar, Gmail, GitHub, Slack,
  Linear, Notion, Vercel, Sentry, Asana, Discord, or Google Docs/Sheets. No API key or credentials
  needed. No setup. Just run the bundled script and it handles everything: grant creation, user
  approval, token caching, and automatic refresh. Do NOT use for API key-based services, bot tokens,
  or when you already have direct credentials.
license: MIT
compatibility: Requires curl and bash. Works with Claude Code, Cursor, OpenClaw, Codex, GitHub Copilot, and any agent with shell access.
metadata:
  author: tapauth
  version: "1.0"
  website: https://tapauth.ai
  docs: https://tapauth.ai/docs
---

# TapAuth — Delegated Access for AI Agents

TapAuth lets your agent get OAuth tokens from users without handling credentials directly.
The user approves in their browser. You get a scoped token. That's it.

## How It Works

This skill includes a CLI script at `scripts/tapauth.sh`. Use it inline with curl:

```bash
curl -H "Authorization: Bearer $(scripts/tapauth.sh google calendar.readonly)" \
  "https://www.googleapis.com/calendar/v3/calendars/primary/events"
```

That's a complete, working example. The script handles everything:

- **First run:** Creates a grant, prints an approval URL to stderr, polls until the user approves, then outputs the token to stdout.
- **Subsequent runs:** Returns the cached token instantly. Automatically refreshes expired tokens.

The `$(...)` command substitution captures stdout (the token) while the approval URL goes to stderr — so curl gets a clean Bearer token.

## Gotchas

- **No API key or credentials needed.** TapAuth is zero-config. Do not look for API keys, client secrets, or environment variables. Just run the script.
- **Always use the bundled script.** The script is at `scripts/tapauth.sh` inside this skill. Do NOT download it from the website — you already have it.
- **Approval URL goes to stderr, token goes to stdout.** The `$(scripts/tapauth.sh ...)` pattern works because the token is on stdout and the approval URL is on stderr. Don't redirect stderr to stdout or the token will be corrupted.
- **Surface the approval URL to the user.** The script prints it to stderr. The user must click the link, sign in with their account, and approve. Nothing happens until they do.
- **Scopes are provider-specific.** Some providers need them (Google, GitHub, Linear), others don't (Vercel, Notion, Slack). See the Quick Reference table below. Check the provider's reference file (e.g. `references/google.md`) for valid scope values.
- **Tokens are cached automatically.** After the first approval, subsequent runs return the cached token instantly. Don't create new grants when you already have a cached token.
- **Use focused Google providers when possible.** `google_sheets` or `google_docs` give simpler consent screens than `google` with full scopes.

## Quick Reference — Provider + Scopes

Some providers require scopes, others don't. Here's the cheat sheet:

| Provider | Command | Scopes? |
|----------|---------|---------|
| Google Calendar | `scripts/tapauth.sh google calendar.readonly` | **Required** — see `references/google.md` |
| Gmail | `scripts/tapauth.sh google https://www.googleapis.com/auth/gmail.send` | **Required** |
| Google Sheets | `scripts/tapauth.sh google_sheets` | Optional (defaults given) |
| Google Docs | `scripts/tapauth.sh google_docs` | Optional (defaults given) |
| GitHub | `scripts/tapauth.sh github repo` | **Required** — `repo`, `read:user`, etc. |
| Vercel | `scripts/tapauth.sh vercel` | **Not needed** — integration-level |
| Notion | `scripts/tapauth.sh notion` | **Not needed** — integration-level |
| Slack | `scripts/tapauth.sh slack` | **Not needed** — integration-level |
| Asana | `scripts/tapauth.sh asana` | **Not needed** — integration-level |
| Linear | `scripts/tapauth.sh linear read` | **Required** — `read`, `write`, `issues:create` |
| Sentry | `scripts/tapauth.sh sentry project:read` | **Required** |
| Discord | `scripts/tapauth.sh discord identify` | **Required** — `identify`, `guilds`, etc. |

**Key rule:** If a provider uses integration-level scopes (Vercel, Notion, Slack, Asana), just pass the provider name. If it uses per-grant scopes (Google, GitHub, Linear, Sentry, Discord), you must specify what you need.

## Usage Pattern

The pattern is always the same:

```bash
curl -H "Authorization: Bearer $(scripts/tapauth.sh <provider> [scopes])" \
  <api-url>
```

For requests that need a body:

```bash
curl -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh <provider> <scopes>)" \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}' \
  <api-url>
```

If you need the token for multiple requests, capture it once:

```bash
TOKEN=$(scripts/tapauth.sh github repo)

# Use it in multiple calls
curl -H "Authorization: Bearer $TOKEN" \
  "https://api.github.com/user/repos?per_page=5"

curl -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Bug report", "body": "Details here"}' \
  "https://api.github.com/repos/owner/repo/issues"
```

## First-Run Flow

On first run, the script will:

1. Create a grant via the TapAuth API
2. Print an approval URL to stderr — **show this to the user**
3. Poll every 2 seconds (up to 10 minutes) waiting for approval
4. Once approved, output the token to stdout and cache it locally

Example stderr output:
```
Creating grant for google (calendar.readonly)...
Approve access: https://tapauth.ai/approve/abc123
Waiting for approval... (2s) https://tapauth.ai/approve/abc123
Waiting for approval... (4s) https://tapauth.ai/approve/abc123
```

**Important:** Surface the approval URL to the user clearly. They need to click it, sign in, and approve.

## Real-World Examples

### List Google Calendar events

```bash
curl -s -H "Authorization: Bearer $(scripts/tapauth.sh google calendar.readonly)" \
  "https://www.googleapis.com/calendar/v3/calendars/primary/events?maxResults=10&orderBy=startTime&singleEvents=true&timeMin=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

### Read a GitHub repo's issues

```bash
curl -s -H "Authorization: Bearer $(scripts/tapauth.sh github repo)" \
  "https://api.github.com/repos/owner/repo/issues?state=open&per_page=10"
```

### Create a GitHub issue

```bash
curl -s -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh github repo)" \
  -H "Content-Type: application/json" \
  -d '{"title": "Fix login bug", "body": "Steps to reproduce..."}' \
  "https://api.github.com/repos/owner/repo/issues"
```

### Send an email via Gmail

```bash
# Base64-encode the email
EMAIL=$(printf "To: recipient@example.com\r\nSubject: Hello\r\n\r\nMessage body" | base64)

curl -s -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh google https://www.googleapis.com/auth/gmail.send)" \
  -H "Content-Type: application/json" \
  -d "{\"raw\": \"$EMAIL\"}" \
  "https://www.googleapis.com/gmail/v1/users/me/messages/send"
```

### Query Linear issues

```bash
curl -s -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh linear read)" \
  -H "Content-Type: application/json" \
  -d '{"query": "{ issues(first: 10) { nodes { title state { name } } } }"}' \
  "https://api.linear.app/graphql"
```

### Search Notion

```bash
curl -s -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh notion)" \
  -H "Content-Type: application/json" \
  -H "Notion-Version: 2022-06-28" \
  -d '{"query": "meeting notes"}' \
  "https://api.notion.com/v1/search"
```

### List Google Drive files

```bash
curl -s -H "Authorization: Bearer $(scripts/tapauth.sh google drive.readonly)" \
  "https://www.googleapis.com/drive/v3/files?pageSize=10&fields=files(id,name,mimeType)"
```

### List Vercel deployments (no scopes needed)

```bash
curl -s -H "Authorization: Bearer $(scripts/tapauth.sh vercel)" \
  "https://api.vercel.com/v6/deployments?limit=5"
```

## Configuration

**Environment variables:**
- `TAPAUTH_BASE_URL` — Override the base URL (default: `https://tapauth.ai`)
- `TAPAUTH_HOME` — Override the cache directory (takes highest priority)
- `CLAUDE_PLUGIN_DATA` — Stable per-plugin directory provided by Claude Code (used automatically if set)

**Cache directory priority:** `TAPAUTH_HOME` > `CLAUDE_PLUGIN_DATA` > `./.tapauth`

**Caching:** Tokens are stored in the cache directory (mode 700, files mode 600). Each provider+scope combination gets its own cache file with the token, expiry, grant ID, and grant secret for automatic refresh.

## Supported Providers

See `references/` for provider-specific scopes, examples, and API details:

| Provider | ID | Scopes Reference |
|----------|----|------------------|
| GitHub | `github` | `references/github.md` |
| Google (multi-service) | `google` | `references/google.md` |
| Gmail | `google` with gmail scopes | `references/gmail.md` |
| Google Sheets | `google_sheets` | `references/google_sheets.md` |
| Google Docs | `google_docs` | `references/google_docs.md` |
| Linear | `linear` | `references/linear.md` |
| Vercel | `vercel` | `references/vercel.md` |
| Notion | `notion` | `references/notion.md` |
| Slack | `slack` | `references/slack.md` |
| Sentry | `sentry` | `references/sentry.md` |
| Asana | `asana` | `references/asana.md` |
| Discord | `discord` | `references/discord.md` |

> **Tip:** Use `google_sheets` or `google_docs` when you only need one Google service.
> Use `google` when you need multiple services (Drive, Calendar, Gmail, Contacts).

To list all providers and valid scopes programmatically:

```bash
curl -s https://tapauth.ai/api/v1/providers
```

## Provider Notes

- **GitHub:** The `repo` scope grants read/write to repositories. Use `read:user` for profile info only.
- **Google:** All Google providers support automatic token refresh. Use focused providers (`google_sheets`, `google_docs`) for simpler consent screens.
- **Notion/Slack/Vercel/Asana:** Scopes are fixed at integration level. No scope argument needed — just pass the provider name.
- **Linear:** Requires explicit scopes (`read`, `write`, etc.) despite being an integration.
- **Discord:** User OAuth tokens, not bot tokens. Tokens expire after ~7 days with automatic refresh.

## Token Lifetimes & Revocation

TapAuth uses zero-knowledge encryption — tokens are encrypted with your `grant_secret`, which TapAuth never stores. This means:

- **TapAuth cannot revoke tokens at the provider level.** We literally cannot decrypt them.
- When a grant expires, the encrypted ciphertext is deleted without ever being read.
- Short-lived tokens (Google ~1hr, Linear ~1hr, Sentry ~8hr) expire naturally and auto-refresh.
- Long-lived tokens (GitHub, Slack, Vercel, Notion) must be revoked in provider settings if needed.

## Common Patterns

### Ask the user to approve, then proceed
```
1. Run scripts/tapauth.sh <provider> <scopes>
2. It prints an approval URL to stderr — show this to the user
3. It polls automatically until approved (up to 10 minutes)
4. Use the returned token in your API calls
```

### Handle expiry gracefully
If the cached token has expired, the script automatically refreshes it. If refresh fails, delete `.tapauth/` and re-run to create a fresh grant.

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
| Token expired / 401 on API call | Cached token expired, refresh failed | Delete `.tapauth/` and re-run to create a fresh grant |
| Approval URL not visible | stderr suppressed by agent runtime | Capture stderr separately or check `.tapauth/` for pending grant files |
| `tapauth: timed out after 600s` | User didn't approve within 10 minutes | Re-run to create a new grant with a fresh approval URL |

## OpenClaw Secrets Provider

TapAuth supports the OpenClaw exec secrets provider protocol via the `tapauth-secrets` script. This lets OpenClaw agents resolve OAuth tokens as secrets at startup.

Configure in your OpenClaw agent config:

```json
{
  "secrets": {
    "tapauth": {
      "source": "exec",
      "command": ["/path/to/tapauth-secrets"],
      "passEnv": ["HOME", "TAPAUTH_HOME", "TAPAUTH_BASE_URL"]
    }
  }
}
```

Reference tokens as `tapauth.provider/scopes` (e.g. `tapauth.google/calendar.readonly`).

**Note:** Grants must be pre-approved — `tapauth-secrets` uses a 10-second timeout and cannot prompt for interactive approval.
