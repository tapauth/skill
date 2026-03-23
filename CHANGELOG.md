# Changelog

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
