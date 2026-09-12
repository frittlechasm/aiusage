Keep only durable, repo-specific rules here; leave shared preferences to global instructions and skills.

# Docs

- Keep usage and provider notes in `README.md`, and terminology in `CONTEXT.md`.

# Runtime constraints

- Keep the shipped CLI in one self-contained Bash script (`aiusage`).
- Installers, docs, tests, and design artifacts are separate from this constraint.
- Keep required runtime dependencies to `bash`, `curl`, `jq`, and standard OS tools.
- Existing optional provider tools must stay optional; see `README.md`.
- Support macOS Bash 3.2 and Linux Bash; avoid Bash 4-only syntax.
- Guard OS-specific commands with portable alternatives.

# Provider behavior

- Base parsers and compatibility fallbacks on verified response shapes.
- Missing quota fields must not become fabricated usage bars.
- Keep provider failures isolated so successful results still render.
- Use Copilot-specific credentials, never `GH_TOKEN` or `GITHUB_TOKEN`: the GitHub CLI account may differ from the Copilot account.
- Keep TTY loading to one status line, then print results once.
- Redirected output must stay free of animation and ANSI escapes.

# Verification

- Add or update behavioral tests for feature changes and bug fixes.
- Test strict-mode failures through the CLI or an explicitly strict subprocess: `tests/helpers/common.bash` disables `set -euo pipefail`.
- After repository changes, run `./tests/run_tests` and require zero failures.
- Report platform skips or blocked checks explicitly.
