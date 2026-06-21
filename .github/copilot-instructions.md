# Copilot Project Instructions

This repository is a cross-platform autonomous task runner.

## Project purpose
- Run pending tasks from tasks.md through an agent CLI.
- Support both Linux and Windows startup mechanisms.
- Keep orchestration logic stable and deterministic.

## Core architecture
- pc-server/src/index.ts exposes:
  - POST /run
  - POST /stop
  - GET /status
- pc-server/src/orchestrator.ts:
  - parses tasks.md
  - expands paths (~ and ${VAR})
  - chooses AGENT_CLI (copilot|claude)
  - executes one task at a time
  - marks completed tasks [x]
- bot/src/index.ts:
  - Telegram polling
  - POST /session-start trigger endpoint

## Agent backend rules
- AGENT_CLI default is copilot.
- copilot success = exit code 0.
- claude success = exit code 0 and JSON output with no is_error.
- Keep prompts single-line when passed to CLI processes.
- Prefer passing prompt by environment variable in Windows commands.

## Cross-platform rules
- Never hardcode user-specific absolute paths.
- Use PROJECTS_ROOT in tasks.md examples.
- Keep Linux automation in scripts/linux (systemd user units + timer).
- Keep Windows automation in scripts/windows (Task Scheduler scripts).

## Editing rules
- Make the smallest change required.
- Preserve existing APIs and endpoint behavior unless explicitly requested.
- Avoid adding dependencies unless clearly needed.
- If changing task parsing format, update tasks.md comments and docs.

## Verification expectations
- Build both packages after TypeScript changes:
  - cd pc-server && npm run build
  - cd bot && npm run build
- Validate both AGENT_CLI modes when changing orchestrator behavior.
