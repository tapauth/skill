---
name: tapauth
description: >-
  Delegated access provider for OpenClaw agents — OAuth tokens for Google Calendar, Gmail, GitHub,
  Slack, Linear, Notion, Vercel, Sentry, Asana, Discord, or Apify, plus user-supplied passwords
  or fixed API keys through the special secret provider. Integrates with OpenClaw's exec secrets
  provider so approved values are resolved at startup and held in memory.
license: MIT
compatibility: Requires curl and bash. Designed for OpenClaw's exec secrets provider.
metadata:
  author: tapauth
  version: "1.0"
  website: https://tapauth.ai
  docs: https://tapauth.ai/docs
---

# TapAuth — Delegated Access via OpenClaw Secrets Manager

TapAuth provides OAuth tokens and approved fixed secrets through OpenClaw's exec secrets provider. Values are resolved at gateway startup and held in memory — they never appear in shell commands or config files as plaintext.

**You must NEVER use `tapauth.sh --token` directly in shell commands, curl calls, or `$(...)` substitutions.** Approved values are always resolved through the secrets manager. Your job as an agent is to configure the secrets provider, not to fetch tokens or secrets yourself.

## When a user asks you to do something that needs delegated access

Follow these steps **in order**. Do not skip to step 3. Do not run `--token` yourself.

### 1. Create a grant and show the approval URL

Run the script **without `--token`** to create a grant. Set `TAPAUTH_HOME` so the grant cache is stored in a stable location that the exec provider can also find:

```bash
TAPAUTH_HOME=/home/node/.tapauth /home/node/.openclaw/skills/tapauth/scripts/tapauth.sh <provider> <scopes>
```

Example for Google Calendar:
```bash
TAPAUTH_HOME=/home/node/.tapauth /home/node/.openclaw/skills/tapauth/scripts/tapauth.sh google calendar.readonly
```

Output:
```text
Approve access: https://tapauth.ai/approve/abc123

Show this URL to the user. Once they approve, run with --token to retrieve it.
```

**Show the approval URL to the user and ask them to approve.** Wait for them to confirm before proceeding.
That final line is the script's generic output. In OpenClaw, do not run `--token` yourself — proceed to step 2 and let the secrets manager invoke it.

### 2. Configure the exec secrets provider in openclaw.json

After the user confirms they approved, **edit `~/.openclaw/openclaw.json`** to add an exec provider under `secrets.providers`:

```json
{
  "secrets": {
    "providers": {
      "tapauth_google_calendar": {
        "source": "exec",
        "command": "/home/node/.openclaw/skills/tapauth/scripts/tapauth.sh",
        "args": ["--token", "google", "calendar.readonly"],
        "passEnv": ["HOME"],
        "env": {"TAPAUTH_HOME": "/home/node/.tapauth"},
        "jsonOnly": false
      }
    }
  }
}
```

**Key fields:**
- **`command`**: Absolute path to `scripts/tapauth.sh` in this skill directory
- **`args`**: `["--token", "<provider>", "<scopes>"]` — must match the grant you created in step 1
- **`jsonOnly: false`**: The script outputs a raw token string, not JSON
- **`passEnv`**: Must include `HOME`
- **`env.TAPAUTH_HOME`**: Must be `/home/node/.tapauth` — the same path used when creating the grant in step 1

Use the naming convention `tapauth_<provider>` or `tapauth_<provider>_<scope>` for the provider key.

### 3. Reload secrets and confirm

After editing `openclaw.json`, run:

```bash
openclaw secrets reload
```

This tells the gateway to re-resolve all secret providers. The exec provider runs `tapauth.sh --token` in the background and stores the result in the in-memory secrets snapshot.

**Tell the user the setup is complete.** The approved value is now resolved and will be available at every gateway startup. If the user repeats their request in a new session, it will already be available.

If you need to verify immediately, run `openclaw secrets reload` and then retry the user's request through the normal OpenClaw secret path. Do not invoke `tapauth.sh --token` directly.

## Rules

- **NEVER run `tapauth.sh --token` directly.** Do not use it in `$(...)`, do not capture its output, do not pipe it to curl. The secrets manager runs it for you.
- **NEVER skip the approval step.** Always create the grant first (step 1), get user approval, then configure the provider (step 2).
- **OAuth is zero-config.** Do not look for OAuth client secrets or provider environment variables.
- **Manual secrets use `secret`.** Use args like `["--token", "secret", "OpenAI API key for staging", "^sk-"]`.
- **Secret expiry is TapAuth-side only.** When a fixed secret grant expires, TapAuth stops returning it, but the underlying password/API key remains valid until the user rotates or revokes it at the source.
- **Always use absolute paths** for the `command` field in the exec provider config.

## Quick Reference — Provider + Scopes

| Provider | Args for exec provider | Scopes Reference |
|----------|----------------------|------------------|
| Google Calendar | `["--token", "google", "calendar.readonly"]` | `references/google.md` |
| Google Drive | `["--token", "google", "drive.readonly"]` | `references/google.md` |
| Google Sheets | `["--token", "google", "spreadsheets.readonly"]` | `references/google.md` |
| Gmail | `["--token", "google", "gmail.send"]` | `references/gmail.md` |
| GitHub | `["--token", "github", "repo"]` | `references/github.md` |
| Vercel | `["--token", "vercel", "deployment"]` | `references/vercel.md` |
| Notion | `["--token", "notion", "read_content"]` | `references/notion.md` |
| Slack | `["--token", "slack", "users:read"]` | `references/slack.md` |
| Asana | `["--token", "asana", "tasks:read"]` | `references/asana.md` |
| Linear | `["--token", "linear", "read"]` | `references/linear.md` |
| Sentry | `["--token", "sentry", "project:read"]` | `references/sentry.md` |
| Discord | `["--token", "discord", "identify"]` | `references/discord.md` |
| Apify | `["--token", "apify", "full_api_access"]` | `references/apify.md` |
| Manual Secret | `["--token", "secret", "OpenAI API key for staging", "^sk-"]` | Description required; regex optional |

Multiple scopes: comma-separate in a single string, e.g. `["--token", "google", "calendar.readonly,drive.readonly"]`.

## Token Lifecycle

- **Resolution:** Fresh tokens fetched at each gateway startup and `openclaw secrets reload`.
- **Caching:** `tapauth.sh` caches tokens locally with expiry. Subsequent calls return instantly if valid.
- **Refresh:** Expired tokens are refreshed automatically from the TapAuth API. No user interaction needed.
- **Re-approval:** If a grant is revoked, delete `~/.tapauth/<provider>-<scopes>.env` and re-run `scripts/tapauth.sh` to create a new grant.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `token refresh failed` | Grant revoked or expired | Delete `~/.tapauth/<provider>-<scopes>.env`, re-run `scripts/tapauth.sh` |
| Token works locally but not in OpenClaw | `passEnv` missing `HOME` | Add `HOME` to `passEnv` array |
| `command must be absolute path` | Relative path in `command` | Resolve `scripts/tapauth.sh` to its absolute path |
| Symlink error | Skill installed via symlink | Add `allowSymlinkCommand: true` and `trustedDirs` to provider config |
| `tapauth: timed out` | Grant not pre-approved | Run `scripts/tapauth.sh <provider> <scopes>` without `--token` first |
