# CLAUDE.md

Guide for running autonomous agent tasks on Windows or Linux.

## What this repo does

Runs an autonomous agent on your personal computer during periods of inactivity. A Telegram bot notifies you; if no reply within 30 minutes, it triggers the orchestrator to run pending tasks from `tasks.md` using either **Copilot CLI** or **Claude CLI** (configurable).

Three local processes (platform-specific startup):
- **pc-server** (port 3333) — HTTP server with endpoints: `POST /run`, `POST /stop`, `GET /status`
- **bot** (port 8080) — Telegram bot + cron webhook
- **Session trigger** — fires hourly at hh:05 (Windows: Task Scheduler; Linux: systemd timer)

## Supported Operating Systems

- **Linux** (Arch, Ubuntu, Debian, Fedora, etc.) — systemd user services
- **Windows** — Task Scheduler jobs
- **macOS** — systemd user services (same as Linux setup)

## Build commands

```bash
cd pc-server && npm install && npm run build
cd ../bot && npm install && npm run build
```

Both use TypeScript. No test suite or lint step.

## Configuration

### Environment variables

**PC Server** (`pc-server/.env` or environment):
- `AGENT_CLI` — `"copilot"` (default) or `"claude"`
  - **copilot**: Uses GitHub Copilot CLI (requires: `copilot login`)
  - **claude**: Uses Anthropic Claude CLI (requires: `claude login`)
- `PROJECTS_ROOT` — Base path for `${PROJECTS_ROOT}` expansion in tasks.md
  - Example: `/home/user/repositories` or `C:\Users\User\repositories`
- `PORT` — HTTP server port (default: 3333)

**Bot** (`bot/.env`):
- `TELEGRAM_BOT_TOKEN` — Get from [@BotFather](https://t.me/botfather)
- `TELEGRAM_CHAT_ID` — Your numeric Telegram ID (use [@userinfobot](https://t.me/userinfobot))
- `PC_WEBHOOK_URL` — URL where pc-server is reachable (default: `http://localhost:3333`)
- `TIMEOUT_MINUTES` — Delay before auto-start (default: 30)
- `CRON_PORT` — Bot's HTTP port for cron triggers (default: 8080)

### tasks.md format

```markdown
## project: <name>
path: ${PROJECTS_ROOT}/repo-name  # or ~/path/to/repo (~ expands to home dir)
context: one-line description

- [ ] task description | priority: high|medium|low
- [x] completed task   | priority: high     # orchestrator writes this
```

Paths support:
- `~` → expands to home directory
- `${VAR}` → expands from environment variables (e.g., `${PROJECTS_ROOT}`)

## Setup — Linux

### Prerequisites
- Node.js 18+ installed
- Copilot CLI: `npm install -g @microsoft/copilot` + `copilot login`
  - OR Claude CLI: `npm install -g @anthropic-ai/claude-code` + `claude login`
- `bot/.env` created with Telegram credentials

### Install systemd services

```bash
# 1. Build both packages
cd pc-server && npm install && npm run build
cd ../bot && npm install && npm run build

# 2. Create .env files from examples
cp pc-server/.env.example pc-server/.env
cp bot/.env.example bot/.env
# Edit both with your actual values (PROJECTS_ROOT, Telegram tokens)

# 3. Run installer
bash scripts/linux/install.sh
```

This will:
- Copy systemd unit files to `~/.config/systemd/user/`
- Enable `pc-server`, `bot`, and `session-trigger.timer`
- Start all services
- Enable lingering so services run while logged off

### Verify installation

```bash
systemctl --user status pc-server
systemctl --user status bot
systemctl --user list-timers session-trigger.timer
journalctl --user -u pc-server -f  # tail logs
```

### Uninstall

```bash
systemctl --user stop pc-server bot session-trigger.timer
systemctl --user disable pc-server bot session-trigger.timer
rm ~/.config/systemd/user/pc-server.service ~/.config/systemd/user/bot.service
rm ~/.config/systemd/user/session-trigger.{service,timer}
systemctl --user daemon-reload
```

## Setup — Windows

### Prerequisites
- Node.js 18+ installed
- Copilot CLI: `npm install -g @microsoft/copilot` + `copilot login`
  - OR Claude CLI: `npm install -g @anthropic-ai/claude-code` + `claude login`
- `bot\.env` created with Telegram credentials
- Administrator access to register Task Scheduler jobs

### Install Task Scheduler jobs

```powershell
# 1. Build both packages
cd pc-server
npm install
npm run build

cd ..\bot
npm install
npm run build

# 2. Create .env files from examples
copy pc-server\.env.example pc-server\.env
copy bot\.env.example bot\.env
# Edit both with your actual values (PROJECTS_ROOT, Telegram tokens)

# 3. Right-click scripts\windows\register-startup.bat → Run as Administrator
```

This will register three Task Scheduler jobs under `ClaudeAutonomous\`:
- **PCServer** — starts 30s after login (port 3333)
- **Bot** — starts 60s after login (port 8080)
- **SessionTrigger** — fires every hour at hh:05

### Verify installation

```powershell
schtasks /query /tn "ClaudeAutonomous\*" /fo list /v

# Manually trigger pc-server
schtasks /Run /TN "ClaudeAutonomous\PCServer"

# Check if it's running
Invoke-RestMethod -Uri http://localhost:3333/status
```

### Uninstall

```powershell
schtasks /Delete /TN "ClaudeAutonomous\PCServer" /F
schtasks /Delete /TN "ClaudeAutonomous\Bot" /F
schtasks /Delete /TN "ClaudeAutonomous\SessionTrigger" /F
```

## Running locally for debug

### Linux

```bash
# Set environment and run
export AGENT_CLI=copilot
export PROJECTS_ROOT=~/repositories
node pc-server/dist/index.js

# In another terminal, trigger a run
curl -X POST http://localhost:3333/run
```

### Windows (PowerShell)

```powershell
$env:AGENT_CLI = "copilot"
$env:PROJECTS_ROOT = "C:\Users\YourName\repositories"

node pc-server/dist/index.js

# Trigger a run
Invoke-RestMethod -Uri http://localhost:3333/run -Method POST | ConvertTo-Json -Depth 5
```

## Architecture

### pc-server (`pc-server/src/`)

**index.ts** — HTTP server with three routes:
- `POST /run` — start orchestrator (returns completed/skipped/errors)
- `POST /stop` — gracefully stop running agent
- `GET /status` — check if agent is running

**orchestrator.ts** — task runner that:
- Parses `tasks.md` (supports `~` and `${VAR}` path expansion)
- Spawns agent CLI (`copilot` or `claude` based on `AGENT_CLI` env)
- Evaluates results:
  - **Copilot**: success = exit code 0
  - **Claude**: success = exit 0 AND no `is_error` in JSON output
- Marks completed tasks with `[x]`

### bot (`bot/src/index.ts`)

Single file that runs two servers in one process:
- **Telegram polling** — responds to commands (`/run`, `/stop`, `/status`, yes/no)
- **HTTP webhook** (port `CRON_PORT`) — `/session-start` endpoint fired by hourly trigger

Session flow:
1. Hourly trigger fires → `POST /session-start` on bot
2. Bot sends Telegram message with 30-minute countdown
3. User replies `yes`/`no`/nothing
4. If `no` or timeout → bot calls `POST /run` on pc-server
5. Agent runs tasks → bot reports results via Telegram

### tasks.md format and parsing

Parser regex for pending tasks:
```
^- \[ \] (.+?) \| priority: (high|medium|low)
```

The space inside `[ ]` is required. Tasks missing `| priority:` are skipped.

Path expansion order:
1. Leading `~` → `os.homedir()`
2. `${VAR}` tokens → `process.env[VAR]`
3. Missing env vars logged with warning; path left as-is

Example:
```
path: ${PROJECTS_ROOT}/biomarker-pipeline
# If PROJECTS_ROOT=/home/alice/repos →
# expands to: /home/alice/repos/biomarker-pipeline
```

## Choosing an agent: Copilot vs. Claude

| Feature | Copilot CLI | Claude CLI |
|---------|-------------|-----------|
| **Installation** | `npm i -g @microsoft/copilot` | `npm i -g @anthropic-ai/claude-code` |
| **Login** | `copilot login` | `claude login` |
| **Headless mode** | `copilot -p "..."` | `claude -p "..." --output-format json` |
| **JSON output** | No (success = exit 0) | Yes (includes `is_error`, `num_turns`, `cost_usd`) |
| **Supported OS** | Linux, macOS, Windows | Linux, macOS, Windows |
| **Cost tracking** | Not visible | Shows `$cost_usd` per task |

**Recommendation**: Start with Copilot (default); both work equally well.

## Key known issues / gotchas

**Prompt must be single-line.** On Windows, `spawnSync` uses PowerShell; on Linux/macOS, it's a direct spawn. The prompt is passed via `AGENT_PROMPT` env var to avoid shell quoting issues.

**Project path must exist.** If `path:` in `tasks.md` points to a non-existent directory, the orchestrator logs a clear error and skips the task.

**Env var expansion is lenient.** If `${VAR}` is not set in environment, it's left as-is in the path (with a warning). Use `PROJECTS_ROOT` for portable paths.

**Systemd timer persistence.** On Linux, `Persistent=true` in the timer ensures that if the hourly trigger fires while the system is asleep, it runs on wake-up.

## Architecture diagrams

**Startup (Linux)**:
```
systemd user session
  ├─ pc-server.service → node pc-server/dist/index.js
  ├─ bot.service → node bot/dist/index.js
  └─ session-trigger.timer (fires hourly)
      └─ session-trigger.service → curl POST /session-start
```

**Startup (Windows)**:
```
Task Scheduler (ClaudeAutonomous\)
  ├─ PCServer (at login +30s) → wscript launch-pcserver.vbs
  ├─ Bot (at login +60s) → wscript launch-bot.vbs
  └─ SessionTrigger (hourly at hh:05) → curl POST /session-start
```

**Task execution**:
```
orchestrator.parseTasks()
  ├─ expand paths (~ and ${VAR})
  ├─ sort by priority
  └─ for each pending task:
      ├─ spawn agent (copilot or claude)
      ├─ evaluate result
      ├─ mark [x] if ok
      └─ log error if not
```

## Troubleshooting

**"Unknown agent CLI: X"** → Check `AGENT_CLI` env var is `"copilot"` or `"claude"`

**Systemd service won't start** → `journalctl --user -u pc-server -n 50` to see errors

**"path does not exist"** → Verify `${PROJECTS_ROOT}` or `~` expands to a real directory

**Copilot/Claude not found** → Install globally and login:
```bash
npm install -g @microsoft/copilot && copilot login
# or
npm install -g @anthropic-ai/claude-code && claude login
```

**Telegram bot not responding** → Check bot/.env has correct `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`

**PC Server not reachable from bot** → Verify `PC_WEBHOOK_URL` in bot/.env matches where pc-server is running

