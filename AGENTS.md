- Keep this file small and concise.
- Update this file only when you have a new learning or a new rule is introduced.

# Docs
- See `README.md` for implementation details and provider notes.

# Task Rules:
- When adding or changing a feature, add or update the corresponding tests.
- Never consider a task complete until `./tests/run_tests` passes with no failures.
- Before every commit, stage changes and run all three secret scanners to ensure we are not checking in any sensitive keys:
  - `gitleaks git --staged`
  - `trufflehog git file://$(pwd) --no-update`
  - `detect-secrets scan`

# Architecture Restraints
- Single self-contained bash script (`aiusage`).
- No external dependencies beyond `bash`, `curl`, and `jq`. Keep it that way.
- Must run correctly on both macOS and Linux.

