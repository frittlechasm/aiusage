- Keep this file small and concise.
- Update this file only when you have a new learning or a new rule is introduced.

# Docs
- See `README.md` for implementation details and provider notes.
- See `CONTEXT.md` for project terminology.

# Task Rules:
- When adding or changing a feature, add or update the corresponding tests.
- Never consider a task complete until `./tests/run_tests` passes with no failures.

# Architecture Restraints
- Single self-contained bash script (`aiusage`).
- No external dependencies beyond `bash`, `curl`, and `jq`. Keep it that way.
- Must run correctly on both macOS and Linux.
