# Changelog

## [1.0.2] - 2026-03-27

- Security: stop caching bearer tokens on disk; cache only grant credentials
- Fix: recreate dead grants automatically in URL mode and fail fast in `--token`
- Docs: align OpenClaw cache-directory guidance and timeout behavior

## [1.0.1] - 2026-03-26

- Security: replace eval/source with explicit allowlisted KEY=VALUE parser
- Security: use long-form curl flags (--silent --show-error) for better error visibility

## [1.0.0] - 2026-03-23

- Consolidated API under /api/v1/ prefix
- Collapsed grant endpoints: GET /api/v1/grants/{id} handles status polling and token retrieval
- .env response format via Accept: text/plain (zero JSON parsing in bash)
- Removed API key requirement — grant_secret is the only credential
- Scopes optional for integration providers (Vercel, Slack, Notion, etc.)
- agent_name optional
- Shell injection protection: grep filter before eval
- Provider name validation against path traversal
- Form-encoded grant creation support

## [0.1.0] - 2026-02-24

- Initial release
