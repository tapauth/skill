# OpenClaw Integration

TapAuth works with [OpenClaw's exec secrets provider](https://docs.openclaw.ai/gateway/secrets) to resolve fresh OAuth tokens at startup. Tokens are held in memory only — they never touch disk as plaintext config.

## How It Works

1. **One-time setup:** Run `tapauth.sh <provider> <scopes>` to create a grant and approve it in the browser. Grant credentials (ID + secret) are saved to `~/.tapauth/`.
2. **Configure OpenClaw:** Add one exec provider per grant with `jsonOnly: false`. OpenClaw runs `tapauth.sh --token <provider> <scopes>` and reads the token from stdout.
3. **Runtime:** OpenClaw resolves tokens at startup into an in-memory snapshot. `tapauth.sh` handles refresh automatically — if the cached token is expired, it fetches a fresh one from the TapAuth API.

## Prerequisites

- `tapauth.sh` with `--token` flag support (the two-step approval flow)
- An approved grant for each provider/scope combination

## Setup

### 1. Create and approve grants

```bash
# Each command creates a grant, prints an approval URL, and polls until approved
scripts/tapauth.sh github repo
scripts/tapauth.sh google calendar.readonly
scripts/tapauth.sh slack channels:read,channels:history
```

> **Note:** All providers require explicit scopes. Run `tapauth.sh <provider> help` or check the API error response for valid scope names.

### 2. Configure exec providers

Add to `~/.openclaw/openclaw.json`:

```json5
{
  secrets: {
    providers: {
      tapauth_github: {
        source: "exec",
        command: "/path/to/skills/tapauth/scripts/tapauth.sh",
        args: ["--token", "github", "repo"],
        passEnv: ["HOME"],
        jsonOnly: false,
      },
      tapauth_google: {
        source: "exec",
        command: "/path/to/skills/tapauth/scripts/tapauth.sh",
        args: ["--token", "google", "calendar.readonly"],
        passEnv: ["HOME"],
        jsonOnly: false,
      },
      tapauth_slack: {
        source: "exec",
        command: "/path/to/skills/tapauth/scripts/tapauth.sh",
        args: ["--token", "slack", "channels:read,channels:history"],
        passEnv: ["HOME"],
        jsonOnly: false,
      },
    },
  },
}
```

> Use the absolute path to `tapauth.sh`. If installed via ClawHub: `~/.openclaw/skills/tapauth/scripts/tapauth.sh`.

### 3. Reference tokens in config

Use SecretRefs wherever OpenClaw accepts them:

```json5
{
  // Example: GitHub token for gh CLI
  tools: {
    github: {
      token: { source: "exec", provider: "tapauth_github", id: "value" },
    },
  },
}
```

The `id` is always `"value"` since each provider returns a single token on stdout.

## Token Lifecycle

- **Resolution:** Fresh tokens fetched at each OpenClaw activation (startup + reload).
- **Caching:** `tapauth.sh` caches tokens locally with expiry. Subsequent calls return instantly if the token is still valid.
- **Refresh:** When cached tokens expire, `tapauth.sh` fetches a fresh one from the TapAuth API. TapAuth handles OAuth refresh server-side.
- **Re-approval:** If a grant is revoked, `tapauth.sh` exits with an error. Delete the cache file and re-run to create a new grant.
- **Manual reload:** `openclaw secrets reload` forces re-resolution without restart.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `token refresh failed` | Grant revoked or expired | Delete `~/.tapauth/<provider>-<scopes>.env`, re-run `tapauth.sh` |
| Token works locally but not in OpenClaw | `passEnv` missing `HOME` | Add `HOME` to `passEnv` array |
| `command must be absolute path` | Relative path in `command` | Use full path: `/Users/you/.openclaw/skills/tapauth/scripts/tapauth.sh` |
| Symlink error | Homebrew or similar | Add `allowSymlinkCommand: true` and `trustedDirs` to provider config |
