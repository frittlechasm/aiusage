- Keep this file small and concise.
- Update this file only when you have a new learning or a new rule is introduced.

- Single self-contained bash script (`aiusage`). No build, test, or lint pipeline.
- No external dependencies beyond `bash`, `curl`, and `jq` — keep it that way.
- Must run correctly on both macOS and Linux.
- New providers: add a `fetch_<provider>()` function, register in `run_all_parallel()` and the main argument parser. See `TODO.md` for the implementation checklist.
