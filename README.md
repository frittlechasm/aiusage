![aiusage screenshot](img.png)

# aiusage

Simple CLI command to check usage limits of your AI Subscription usage. 

Currently supports : 
- Claude 
- Codex 
- Gemini CLI
- JetBrains AI

Planned next:
- Cursor
- GitHub Copilot

## Features
- Shows `5h` and `Weekly` usage bars for Claude
- Shows `5h` and `Weekly` usage bars for Codex
- Shows Gemini CLI quota usage for Google OAuth / Code Assist accounts
- Shows JetBrains AI credit usage from local IDE quota state
- Shows local reset time for each usage window (when available)
- No web scraping
- Single bash script

## Requirements
- `bash`
- `curl`
- `jq`
- Authenticated local CLIs (`claude`, `codex`, and/or `gemini`) and/or a local JetBrains IDE with AI Assistant enabled

## Install
```bash
chmod +x ./aiusage
```

## Usage
```bash
./aiusage

# Claude only
./aiusage claude

# Codex only
./aiusage codex

# Gemini only
./aiusage gemini

# JetBrains only
./aiusage jetbrains
```

## Notes
- This script reads local auth state from your machine and then calls provider backend endpoints.
  (for example `~/.codex/auth.json`, `~/.gemini/oauth_creds.json`, Claude credentials/keychain, and JetBrains local quota files)
- Gemini CLI support uses the local OAuth login created by `gemini` and queries Gemini Code Assist quota endpoints while the local access token is still valid.
- If the Gemini session has expired, re-run `gemini` to refresh the local login before using `aiusage gemini`.
- JetBrains usage is read from the newest local `AIAssistantQuotaManager2.xml` file by modification time under your JetBrains config directory.
- If multiple JetBrains IDE configs exist, `aiusage` picks the most recently updated quota file.
- If auth or endpoint access is unavailable, it renders `unavailable` bars.
- Endpoints and response shapes can change over time.

## Security
> [!IMPORTANT]
> Do not commit your token files.
> Avoid running this script on shared multi-user machines unless you trust the environment.
