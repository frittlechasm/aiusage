![aiusage screenshot](img.png)

# aiusage

Simple CLI command to check usage limits of your AI Subscription usage. 

Currently supports :
- Claude
- Codex
- Cursor
- Gemini CLI
- JetBrains AI
- GitHub Copilot

## Features
- Shows `5h` and `Weekly` usage bars for Claude
- Shows `5h` and `Weekly` usage bars for Codex
- Shows Cursor monthly credit / request usage — auto-detects session from Firefox, Chrome, Arc, Brave, Edge, or Helium; or set `CURSOR_COOKIE` manually
- Shows Gemini CLI quota usage for Google OAuth / Code Assist accounts
- Shows JetBrains AI credit usage from local IDE quota state
- Shows GitHub Copilot `Premium` and `Chat` quota bars — uses `copilot login` or `COPILOT_GITHUB_TOKEN`
- Shows local reset time for each usage window (when available)
- No web scraping
- Single bash script

## Requirements
- `bash`
- `curl`
- `jq`
- Authenticated local CLIs (`claude`, `codex`, and/or `gemini`) and/or a local JetBrains IDE with AI Assistant enabled
- Cursor: `sqlite3` + a supported browser logged in to cursor.com (or set `CURSOR_COOKIE`); Chromium-based browsers also require `python3` and `openssl` for cookie decryption
- Copilot: run `copilot login` or set `COPILOT_GITHUB_TOKEN`

## Install
```bash
chmod +x ./aiusage
```

## Usage
```bash
./aiusage

# Claude only
./aiusage claude

# Cursor + Claude
./aiusage cursor claude

# Any subset, in the order you want
./aiusage codex gemini jetbrains copilot
```

## Notes
- This script reads local auth state from your machine and then calls provider backend endpoints.
  (for example `~/.codex/auth.json`, `~/.gemini/oauth_creds.json`, Claude credentials/keychain, and JetBrains local quota files)
- Gemini CLI support uses the local OAuth login created by `gemini` and queries Gemini Code Assist quota endpoints while the local access token is still valid.
- If the Gemini session has expired, re-run `gemini` to refresh the local login before using `aiusage gemini`.
- JetBrains usage is read from the newest local `AIAssistantQuotaManager2.xml` file by modification time under your JetBrains config directory.
- If multiple JetBrains IDE configs exist, `aiusage` picks the most recently updated quota file.
- Cursor session is read automatically from your browser's cookie store (Firefox via `sqlite3`; Chrome/Arc/Brave/Edge/Helium via `sqlite3` + `python3` + `openssl`). The browser does not need to be open. Alternatively, set `CURSOR_COOKIE` to the value of the `WorkosCursorSessionToken` cookie from browser DevTools.
- Copilot token lookup is intentionally limited to dedicated Copilot auth so it does not accidentally use a different GitHub account: `COPILOT_GITHUB_TOKEN`, the local `aiusage` cache, then the `copilot login` credential store / plaintext `~/.copilot/config.json` fallback. Tokens discovered from the Copilot store/plaintext fallback are cached and the cache is cleared automatically on auth failure.
- Copilot quota bars reflect `Premium` (premium interactions / completions) and `Chat` usage. Unlimited quotas (e.g. Copilot Business chat) are not shown. Plans with no tracked individual quota show the plan name only.
- If auth or endpoint access is unavailable, it renders `unavailable` bars.
- Endpoints and response shapes can change over time.

## Security
> [!IMPORTANT]
> Do not commit your token files.
> Avoid running this script on shared multi-user machines unless you trust the environment.
