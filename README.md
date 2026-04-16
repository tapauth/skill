# TapAuth Agent Skill

> Delegated access broker for AI agents. One API call to connect any OAuth provider.

This is the official [Agent Skill](https://agentskills.io) for [TapAuth](https://tapauth.ai) — the trust layer between humans and AI agents.

## Install

Works with any agent that supports the [Agent Skills standard](https://agentskills.io):

```bash
npx skills add tapauth/skill
```

Compatible with: **Claude Code** · **Cursor** · **OpenClaw** · **OpenAI Codex** · **GitHub Copilot** · **VS Code** · and more.

## What It Does

Gives your AI agent the ability to get OAuth tokens from users. Instead of hardcoding API keys or passing credentials, TapAuth lets users approve access in their browser with granular scope control.

```
Agent creates grant → User approves in browser → Agent gets scoped token
```

No API key needed. No signup needed. The user's approval is the only gate.

## Supported Providers

| Provider | Reference | Scopes |
|----------|-----------|--------|
| GitHub | [references/github.md](references/github.md) | `repo`, `read:user`, `workflow`, etc. |
| Google (multi-service) | [references/google.md](references/google.md) | Drive, Calendar, Sheets, Docs, Contacts |
| Gmail | [references/gmail.md](references/gmail.md) | Read, send, manage emails |
| Linear | [references/linear.md](references/linear.md) | Issues, projects, teams |
| Vercel | [references/vercel.md](references/vercel.md) | Deployments, projects, env vars, domains |
| Notion | [references/notion.md](references/notion.md) | Pages, databases, search |
| Slack | [references/slack.md](references/slack.md) | Channels, messages, users, files |
| Asana | [references/asana.md](references/asana.md) | Tasks, projects, workspaces |
| Discord | [references/discord.md](references/discord.md) | Guilds, channels, messages, users |
| Sentry | [references/sentry.md](references/sentry.md) | Error tracking, projects, organizations |
| Apify | [references/apify.md](references/apify.md) | Actors, web scraping, datasets, automation |

## Quick Example

For OpenClaw, do not capture TapAuth tokens into shell variables. Create the grant, then wire the bundled script into the exec secrets provider described in `SKILL.md`.

```bash
# 1. Create a grant and show the approval URL to the user
TAPAUTH_HOME=/home/node/.tapauth /home/node/.openclaw/skills/tapauth/scripts/tapauth.sh github repo

# 2. After approval, add the exec provider to ~/.openclaw/openclaw.json
# 3. Reload secrets so OpenClaw resolves the token in memory
openclaw secrets reload
```

After that, reference the resolved secret from your OpenClaw config or package instead of using `TOKEN=$(...)`.

### API (v1)

```bash
# 1. Create a grant
curl -X POST https://tapauth.ai/api/v1/grants \
  -H "Content-Type: application/json" \
  -d '{"provider": "github", "scopes": ["repo"]}'

# 2. User clicks the approval_url
# 3. Retrieve the token
curl https://tapauth.ai/api/v1/grants/{grant_id} \
  -H "Authorization: Bearer gs_..."
```

## Links

- 🌐 [tapauth.ai](https://tapauth.ai)
- 📖 [Documentation](https://tapauth.ai/docs)
- 🔐 [Agent Skills Spec](https://agentskills.io)

## License

MIT
