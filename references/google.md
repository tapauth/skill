# Google Workspace via TapAuth

## Available Scopes

Use the Google scope name without the URL prefix. Full URLs also work.

| Scope | Access | Full URL |
|-------|--------|----------|
| `calendar.readonly` | Read calendar events | `https://www.googleapis.com/auth/calendar.readonly` |
| `calendar.events` | Full calendar access | `https://www.googleapis.com/auth/calendar.events` |
| `calendar.events.readonly` | Read calendar events (events-only) | `https://www.googleapis.com/auth/calendar.events.readonly` |
| `spreadsheets.readonly` | Read Google Sheets | `https://www.googleapis.com/auth/spreadsheets.readonly` |
| `spreadsheets` | Full Sheets access | `https://www.googleapis.com/auth/spreadsheets` |
| `documents.readonly` | Read Google Docs | `https://www.googleapis.com/auth/documents.readonly` |
| `documents` | Full Docs access | `https://www.googleapis.com/auth/documents` |
| `userinfo.email` | Read user email | `https://www.googleapis.com/auth/userinfo.email` |
| `userinfo.profile` | Read user profile | `https://www.googleapis.com/auth/userinfo.profile` |

## Example: Read a Google Sheet

```bash
# 1. Get a token
scripts/tapauth.sh google spreadsheets.readonly

# 2. Read a sheet
curl -H "Authorization: Bearer <token>" \
  "https://sheets.googleapis.com/v4/spreadsheets/SPREADSHEET_ID/values/Sheet1"
```

## Example: List Calendar Events

```bash
curl -H "Authorization: Bearer <token>" \
  "https://www.googleapis.com/calendar/v3/calendars/primary/events?maxResults=10&timeMin=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

## Example: Create Calendar Event

```bash
# 1. Get a token with write scope
scripts/tapauth.sh google calendar.events

# 2. Create an event (replace YYYY-MM-DD with a future date)
curl -X POST \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{
    "summary": "Team standup",
    "start": {"dateTime": "YYYY-MM-DDT09:00:00Z"},
    "end":   {"dateTime": "YYYY-MM-DDT09:30:00Z"}
  }' \
  "https://www.googleapis.com/calendar/v3/calendars/primary/events"
```

## Example: Multiple Scopes

```bash
# Comma-separated (required format)
scripts/tapauth.sh google calendar.events,spreadsheets
```

## Gotchas

- **Scope names:** Use Google's actual scope names without the URL prefix (e.g. `calendar.readonly`, not `calendar_read`). Full URLs also work.
- **Token refresh:** Google access tokens expire after ~1 hour. TapAuth handles refresh automatically — just call the token endpoint again to get a fresh token.
- **Unverified app warning:** Users may see a "This app isn't verified" screen. They can click "Advanced" → "Go to TapAuth" to proceed.
- **Readonly preference:** Always prefer read-only scope variants unless you need write access. Higher approval rate.
- **Multiple scopes:** Pass as comma-separated: `spreadsheets.readonly,calendar.readonly`

## Recommended Minimum Scopes

| Use Case | Scopes |
|----------|--------|
| Read calendar | `calendar.readonly` |
| Read + write calendar | `calendar.events` |
| Read spreadsheet | `spreadsheets.readonly` |
| Read document | `documents.readonly` |
| Full workspace | `calendar.events`, `spreadsheets`, `documents` |
