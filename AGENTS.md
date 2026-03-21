- Keep this file small and concise.
- Update this file only when you have a new learning or a new rule is introduced.

# Docs
- check README.md on further details about the implementation 

# Rules
- Must run correctly on both macOS and Linux.
- Single self-contained bash script (`aiusage`). No build, test, or lint pipeline.
- No external dependencies beyond `bash`, `curl`, and `jq` — keep it that way.
- New providers: add a `fetch_<provider>()` function, register in `run_all_parallel()` and the main argument parser. See `TODO.md` for the implementation checklist.
- Before every commit, stage changes and run `gitleaks git --staged`, `trufflehog git file://$(pwd) --no-update`, and `detect-secrets scan`.
