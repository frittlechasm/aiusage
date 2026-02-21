# aiusage

Simple CLI command to check usage limits of your AI Subscription usage. 

Currently supports : 
- Claude 
- Codex 

## Features
- Shows `5h` and `Weekly` usage bars for Claude
- Shows `5h` and `Weekly` usage bars for Codex
- Shows local reset time for each usage window (when available)
- No web scraping
- Single bash script

## Requirements
- `bash`
- `curl`
- `jq`
- Authenticated local CLIs (`claude` and/or `codex`)

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
```

## Notes
- This script reads local auth state from your machine and then calls provider backend endpoints.
  (for example `~/.codex/auth.json` and Claude credentials/keychain)
- If auth or endpoint access is unavailable, it renders `unavailable` bars.
- Endpoints and response shapes can change over time.

## Security
> [!IMPORTANT]
> Do not commit your token files.
> Avoid running this script on shared multi-user machines unless you trust the environment.
