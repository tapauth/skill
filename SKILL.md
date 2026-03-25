---
name: tapauth
description: >-
  Use when you need an OAuth token for a user's account — Google Calendar, Gmail, GitHub, Slack,
  Linear, Notion, Vercel, Sentry, Asana, Discord, or Apify. No API key or credentials needed. No setup.
  Just run the bundled script and it handles everything: grant creation, user approval, token
  caching, and automatic refresh. Do NOT use for API key-based services, bot tokens, or when you
  already have direct credentials.
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

This skill includes a CLI script at `scripts/tapauth.sh` with two modes:

### Step 1 — Get the approval URL (default mode)

```bash
scripts/tapauth.sh google calendar.readonly
```

This creates a grant and prints the approval URL to stdout:
```
Approve access: https://tapauth.ai/approve/abc123

Show this URL to the user. Once they approve, run with --token to get the bearer token.
```

**Show the URL to the user.** They must click it, sign in, and approve. This command exits immediately — it does not block or poll.

### Step 2 — Immediately run the API call with `--token`

```bash
curl -H "Authorization: Bearer $(scripts/tapauth.sh --token google calendar.readonly)" \
  "https://www.googleapis.com/calendar/v3/calendars/primary/events"
```

Run this **right after** showing the URL — do not wait for the user to confirm they approved. The `--token` flag polls automatically (every 5 seconds, up to 10 minutes) until the user approves, then outputs the bearer token to stdout. The `$(...)` substitution feeds it directly into curl.

**Always use `--token` inline with `$(...)`.** Do NOT capture the token into a shell variable like `TOKEN=$(...)`. The inline pattern keeps the token out of shell history and process listings.

**On subsequent runs,** the token is cached. Both modes detect this — default mode prints "Already authorized", and `--token` returns the cached token instantly.

> **⚠️ IMPORTANT: Always run default mode first on first use with a provider.**
>
> Do NOT skip straight to `--token` inside `$(...)` on first run — it will block
> polling for up to 10 minutes while the approval URL is hidden in tool output.
> Run without `--token` first to get the URL, show it to the user, then use `--token`.

## Gotchas

- **No API key or credentials needed.** TapAuth is zero-config. Do not look for API keys, client secrets, or environment variables. Just run the script.
- **Always use the bundled script.** The script is at `scripts/tapauth.sh` inside this skill. Do NOT download it from the website — you already have it.
- **Always run default mode first, then `--token`.** Default mode prints the approval URL to stdout and exits. `--token` mode polls and returns the bearer token. Don't skip to `--token` on first run — the user needs to see and click the approval URL first.
- **Scopes are provider-specific.** Some providers need them (Google, GitHub, Linear), others don't (Vercel, Notion, Slack). See the Quick Reference table below. Check the provider's reference file (e.g. `references/google.md`) for valid scope values.
- **Tokens are cached automatically.** After the first approval, subsequent runs return the cached token instantly. Don't create new grants when you already have a cached token.

## Quick Reference — Provider + Scopes

Scopes are **required** for all providers. Here's the cheat sheet:

| Provider | Command | Scopes |
|----------|---------|--------|
| Google Calendar | `scripts/tapauth.sh google calendar.readonly` | See `references/google.md` |
| Google Drive | `scripts/tapauth.sh google drive.readonly` | See `references/google.md` |
| Google Sheets | `scripts/tapauth.sh google spreadsheets.readonly` | Use `google` provider with sheets scopes |
| Google Docs | `scripts/tapauth.sh google documents.readonly` | Use `google` provider with docs scopes |
| GitHub | `scripts/tapauth.sh github repo` | `repo`, `read:user`, etc. |
| Vercel | `scripts/tapauth.sh vercel deployment` | `deployment`, `project`, etc. |
| Notion | `scripts/tapauth.sh notion read_content` | `read_content`, `update_content`, etc. |
| Slack | `scripts/tapauth.sh slack users:read` | `users:read`, `channels:read`, etc. |
| Asana | `scripts/tapauth.sh asana tasks:read` | `tasks:read`, `projects:read`, etc. |
| Linear | `scripts/tapauth.sh linear read` | `read`, `write`, `issues:create` |
| Sentry | `scripts/tapauth.sh sentry project:read` | `org:read`, `project:read`, etc. |
| Discord | `scripts/tapauth.sh discord identify` | `identify`, `guilds`, etc. |
| Apify | `scripts/tapauth.sh apify full_api_access` | `full_api_access` |

**Key rule:** Always specify the scopes you need. Check the provider's reference file for valid scope values.

## Usage Pattern

The pattern is always the same — **default mode first, then `--token`:**

```bash
# 1. Get the approval URL (show it to the user)
scripts/tapauth.sh <provider> [scopes]

# 2. Use the token
curl -H "Authorization: Bearer $(scripts/tapauth.sh --token <provider> [scopes])" \
  <api-url>
```

For requests that need a body:

```bash
curl -X POST \
  -H "Authorization: Bearer $(scripts/tapauth.sh --token <provider> <scopes>)" \
  -H "Content-Type: application/json" \
  -d '{"key": "value"}' \
  <api-url>
```

For multiple requests, repeat the `$(...)` inline pattern — the token is cached so each call returns instantly:

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
3. Immediately run your `curl` with `$(scripts/tapauth.sh --token <provider> [scopes])` — it polls automatically until the user approves, then returns the bearer token.

Example default-mode output:
```
Approve access: https://tapauth.ai/approve/abc123

Show this URL to the user. Once they approve, run with --token to get the bearer token.
```

Example `--token` mode (polling):
```
Waiting for approval... (2s)
Waiting for approval... (4s)
```

Once approved, the token is cached. Subsequent runs of either mode return instantly.

## Real-World Examples

### List Google Calendar events

```bash
curl -s -H "Authorization: Bearer $(scripts/tapauth.sh --token google calendar.readonly)" \
  "https://www.googleapis.com/calendar/v3/calendars/primary/events?maxResults=10&orderBy=startTime&singleEvents=true&timeMin=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
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

**Caching:** Tokens are stored in the cache directory (mode 700, files mode 600). Each provider+scope combination gets its own cache file with the token, expiry, grant ID, and grant secret for automatic refresh.

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

> The `google` provider covers all Google services (Drive, Calendar, Sheets, Docs, Gmail, Contacts).

To list all providers and valid scopes programmatically:

```bash
curl -s https://tapauth.ai/api/v1/providers
```

## Provider Notes

- **GitHub:** The `repo` scope grants read/write to repositories. Use `read:user` for profile info only.
- **Google:** Supports automatic token refresh. Use the `google` provider for all Google services (Calendar, Sheets, Docs, Drive, Gmail, Contacts).
- **Notion/Slack/Vercel:** Scopes are fixed at integration level but must still be specified.
- **Linear:** Requires explicit scopes (`read`, `write`, etc.).
- **Discord:** User OAuth tokens, not bot tokens. Tokens expire after ~7 days with automatic refresh.
- **Apify:** Uses Dynamic Client Registration (DCR) and PKCE. Only `full_api_access` scope available. Tokens expire and auto-refresh.

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
| Approval URL not visible | Skipped default mode and went straight to `--token` | Run `scripts/tapauth.sh <provider> [scopes]` (without `--token`) first to get the approval URL, show it to the user, then use `--token`. |
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
