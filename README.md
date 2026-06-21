# Autonomous Agent Task Runner

Runs an AI agent (Copilot CLI or Claude Code) on your PC to process pending tasks from `tasks.md`.
Triggered hourly via Telegram, with automatic fallback to agent mode if you don't respond within 30 minutes.
Works on **Windows** (Task Scheduler) and **Linux** (systemd).

No cloud hosting needed, everything runs locally.

---

## Architecture

```
Hourly trigger (Telegram notification)
        │
        ▼
  bot/ (local process)
  POST /session-start
        │
        ▼
  Telegram message → you
        │
        ├── "yes"  → cancels timer, agent idle
        │
        └── "no" or 30 min timeout
                │
                ▼
          POST http://localhost:3333/run
                │
                ▼
          pc-server/ orchestrator
          │
          ├─ read tasks.md
          ├─ expand paths (~ and ${VAR})
          ├─ sort by priority
          │
          └─ for each task:
              ├─ cd to project path
              ├─ spawn agent (copilot or claude)
              ├─ mark [x] when done
              ├─ git commit
              └─ next task
                │
                ▼
          Telegram summary + cost
```

---

## Supported Platforms

- **Windows** — Task Scheduler auto-start + hourly schtask
- **Linux** (Ubuntu, Arch, Debian, Fedora) — systemd user services + timer
- **macOS** — same as Linux (systemd)

---

## Prerequisites: Choose Your Agent

Choose one (not both):

### Option A: Copilot CLI (recommended default)
```bash
npm install -g @microsoft/copilot
copilot login
```

Headless: `copilot -p "your prompt" --allow-all-tools` (exit 0 = success)

### Option B: Claude Code
```bash
npm install -g @anthropic-ai/claude-code
claude login
```

Headless: `claude -p "your prompt" --output-format json` (exit 0 + no `is_error` = success)

---

## Setup: Linux

### 1. Build both packages

```bash
cd pc-server && npm install && npm run build
cd ../bot && npm install && npm run build
```

### 2. Create `.env` files

```bash
cp pc-server/.env.example pc-server/.env
cp bot/.env.example bot/.env
```

Edit both:
- `pc-server/.env`: Set `AGENT_CLI` (copilot|claude) and `PROJECTS_ROOT`
- `bot/.env`: Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`

### 3. Run systemd installer

```bash
bash scripts/linux/install.sh
```

This will:
- Copy systemd units to `~/.config/systemd/user/`
- Enable and start `pc-server`, `bot`, and `session-trigger.timer`
- Enable lingering so services persist while logged off

### 4. Verify

```bash
systemctl --user status pc-server
systemctl --user status bot
systemctl --user list-timers session-trigger.timer
journalctl --user -u pc-server -f  # tail logs
```

### 5. Test end-to-end

```bash
curl -X POST http://localhost:3333/status
curl -X POST http://localhost:8080/session-start  # should send Telegram
```

---

## Setup: Windows

### 1. Build both packages

```powershell
cd pc-server
npm install
npm run build

cd ..\bot
npm install
npm run build
```

### 2. Create `.env` files

```powershell
copy pc-server\.env.example pc-server\.env
copy bot\.env.example bot\.env
```

Edit both:
- `pc-server\.env`: Set `AGENT_CLI` (copilot|claude) and `PROJECTS_ROOT`
- `bot\.env`: Set `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`

### 3. Register Task Scheduler jobs (Administrator required)

```powershell
# Right-click scripts\windows\register-startup.bat → Run as Administrator
```

This registers three jobs under `ClaudeAutonomous\`:

| Task | Trigger | What it runs |
|---|---|---|
| `PCServer` | On login (+30s) | `node pc-server/dist/index.js` |
| `Bot` | On login (+60s) | `node bot/dist/index.js` |
| `SessionTrigger` | Hourly at :05 | `curl POST /session-start` |

### 4. Start tasks immediately

```powershell
schtasks /Run /TN "ClaudeAutonomous\PCServer"
schtasks /Run /TN "ClaudeAutonomous\Bot"
```

### 5. Test end-to-end

```powershell
Invoke-RestMethod -Uri http://localhost:3333/status
Invoke-RestMethod -Uri http://localhost:8080/session-start -Method POST  # should send Telegram
```

---

## Configure PROJECTS_ROOT

The path variable `${PROJECTS_ROOT}` in `tasks.md` must be set in your environment:

**Linux/macOS:**
```bash
export PROJECTS_ROOT=$HOME/repositories
# or in pc-server/.env:
PROJECTS_ROOT=/home/user/repositories
```

**Windows:**
```powershell
$env:PROJECTS_ROOT = "C:\Users\YourName\repositories"
# or in pc-server\.env:
PROJECTS_ROOT=C:\Users\YourName\repositories
```

---

## Adding Tasks

Edit `tasks.md`. Format:

```markdown
## project: biomarkers
path: ${PROJECTS_ROOT}/biomarker-pipeline
context: Python bioinformatics pipeline

- [ ] implement new feature | priority: high
- [ ] refactor tests | priority: medium
- [ ] update docs | priority: low
```

**Rules:**
- `path:` supports `~` (home dir) and `${VARIABLE}` expansion
- Tasks are sorted by priority (`high` → `medium` → `low`)
- Orchestrator auto-marks tasks `[x]` and commits `tasks.md`

---

## Telegram Commands

| Message | Action |
|---|---|
| `yes` | Claim the session — cancels timer, agent idles |
| `no` | Start agent now (don't wait 30 min) |
| `/run` | Start agent manually right now |
| `/stop` | Gracefully stop a running session |
| `/status` | Check if agent is running |
| `/help` | Show command list |

---

## Running Locally (Debug)

**Linux:**
```bash
export AGENT_CLI=copilot
export PROJECTS_ROOT=~/repositories
node pc-server/dist/index.js

# In another terminal:
curl -X POST http://localhost:3333/run
```

**Windows:**
```powershell
$env:AGENT_CLI = "copilot"
$env:PROJECTS_ROOT = "C:\Users\YourName\repositories"
node pc-server/dist/index.js

# In another PowerShell:
Invoke-RestMethod -Uri http://localhost:3333/run -Method POST
```

---

## Troubleshooting

**Telegram bot doesn't send messages**
- Verify `bot/.env` has correct `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`
- Check bot process is running: `systemctl --user status bot` (Linux) or Task Scheduler (Windows)
- Test: `curl -X POST http://localhost:8080/session-start`

**PC Server not responding**
- Verify it's running: `curl http://localhost:3333/status`
- Check logs: `journalctl --user -u pc-server -f` (Linux) or logs file (Windows)

**Agent fails on tasks**
- Verify you're logged in: `copilot -p "test" --allow-all-tools` or `claude -p "test"`
- Confirm project paths in `tasks.md` exist and `${PROJECTS_ROOT}` is set correctly
- Check agent permissions: `AGENT_CLI=copilot` (Copilot) or `AGENT_CLI=claude` (Claude)

**Path variable not expanding**
- Ensure `PROJECTS_ROOT` is set: `echo $PROJECTS_ROOT` (Linux) or `echo $env:PROJECTS_ROOT` (Windows)
- If using `pc-server/.env`, verify the file exists and process reloads it

**Linux systemd not starting**
- Check status: `systemctl --user status pc-server`
- View logs: `journalctl --user -u pc-server -n 50`
- Re-run installer: `bash scripts/linux/install.sh`

**Windows Task Scheduler job doesn't run**
- Verify job exists: `schtasks /Query /TN "ClaudeAutonomous\PCServer"`
- Check last run result: right-click job → Properties → History
- Re-register: right-click `scripts\windows\register-startup.bat` → Run as Administrator

---

## Choosing: Copilot vs. Claude

| | Copilot CLI | Claude CLI |
|---|---|---|
| **Installation** | `npm i -g @microsoft/copilot` | `npm i -g @anthropic-ai/claude-code` |
| **Headless mode** | `copilot -p "..."` | `claude -p "..." --output-format json` |
| **Success indicator** | exit 0 | exit 0 + no `is_error` in JSON |
| **Cost visibility** | No | Yes (`$cost_usd` per task) |
| **OS support** | Linux, macOS, Windows | Linux, macOS, Windows |

**Default:** `AGENT_CLI=copilot`
**To switch:** Change `AGENT_CLI=claude` in `pc-server/.env` or environment

---

## Advanced: Custom Instructions

Native Copilot configuration is included in this repo:

1. `.github/copilot-instructions.md`
2. `.instructions.md`

These files provide repo-specific behavior for Copilot IDE/CLI sessions, including cross-platform rules, task format constraints, and validation expectations.

Example:
```markdown
# Build & Test
- Build: `npm run build`
- Test: `npm test`
- Lint: `npm run lint`

# Code Style
- Use ES6+ syntax
- Max line length: 100
- 2 spaces indentation
```

---

## Architecture Files

- `pc-server/src/orchestrator.ts` — task parser, path expansion, agent spawn
- `pc-server/src/index.ts` — HTTP server (POST /run, /stop, GET /status)
- `bot/src/index.ts` — Telegram polling + cron webhook
- `tasks.md` — task queue (you edit this)
- `scripts/linux/` — systemd units + installer
- `scripts/windows/` — Task Scheduler scripts
