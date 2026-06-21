@echo off
REM ─────────────────────────────────────────────────────────────────────────
REM  register-startup.bat
REM  Register all Task Scheduler jobs for autonomous agent runner
REM  Derives repo path from script location (no hardcoding)
REM
REM  Prerequisites:
REM    1. Node.js installed
REM    2. Copilot CLI installed globally  (npm i -g @anthropic-ai/copilot)
REM       OR Claude Code installed globally  (npm i -g @anthropic-ai/claude-code)
REM    3. Logged in to Copilot/Claude  (copilot/claude login)
REM    4. bot\.env created with TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
REM    5. Both packages built  (npm run build in pc-server\ and bot\)
REM    6. Run this script as Administrator
REM ─────────────────────────────────────────────────────────────────────────

setlocal enabledelayedexpansion

REM Derive REPO from script location: scripts\windows\register-startup.bat -> repo root
for %%I in ("%~dp0..\..") do set REPO=%%~fI

set PCSERVER_DIR=!REPO!\pc-server
set BOT_DIR=!REPO!\bot
set SCRIPTS_DIR=!REPO!\scripts\windows

echo [setup] Repository path: !REPO!
echo [setup] PC Server dir: !PCSERVER_DIR!
echo [setup] Bot dir: !BOT_DIR!
echo.

REM ── Verify prerequisites ──────────────────────────────────────────────────────

if not exist "!PCSERVER_DIR!\dist\index.js" (
  echo [setup] Error: pc-server not built. Run: cd pc-server ^& npm install ^& npm run build
  exit /b 1
)

if not exist "!BOT_DIR!\dist\index.js" (
  echo [setup] Error: bot not built. Run: cd bot ^& npm install ^& npm run build
  exit /b 1
)

if not exist "!BOT_DIR!\.env" (
  echo [setup] Error: bot\.env not found. Create it with TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
  exit /b 1
)

REM ── Register pc-server ────────────────────────────────────────────────────────

echo [setup] Registering PCServer task...
powershell -Command "$a = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument '\"\"\"!SCRIPTS_DIR!\launch-pcserver.vbs\"\"\"' -WorkingDirectory '!PCSERVER_DIR!'; $t = New-ScheduledTaskTrigger -AtLogOn; $t.Delay = 'PT30S'; $s = New-ScheduledTaskSettingsSet -Hidden; $s.DisallowStartIfOnBatteries = $false; $s.StopIfGoingOnBatteries = $false; Register-ScheduledTask -Force -TaskName 'PCServer' -TaskPath '\ClaudeAutonomous\' -Action $a -Trigger $t -Settings $s -RunLevel Highest | Out-Null"

REM ── Register bot ──────────────────────────────────────────────────────────────

echo [setup] Registering Bot task...
powershell -Command "$a = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument '\"\"\"!SCRIPTS_DIR!\launch-bot.vbs\"\"\"' -WorkingDirectory '!BOT_DIR!'; $t = New-ScheduledTaskTrigger -AtLogOn; $t.Delay = 'PT60S'; $s = New-ScheduledTaskSettingsSet -Hidden; $s.DisallowStartIfOnBatteries = $false; $s.StopIfGoingOnBatteries = $false; Register-ScheduledTask -Force -TaskName 'Bot' -TaskPath '\ClaudeAutonomous\' -Action $a -Trigger $t -Settings $s -RunLevel Highest | Out-Null"

REM ── Register session trigger (hourly at hh:05) ─────────────────────────────────

echo [setup] Registering SessionTrigger task...
schtasks /Create /F /TN "ClaudeAutonomous\SessionTrigger" ^
  /TR "C:\Windows\System32\curl.exe -s -X POST http://localhost:8080/session-start" ^
  /SC HOURLY ^
  /MO 1 ^
  /ST 00:05

REM ── Disable battery restrictions on SessionTrigger ───────────────────────────

echo [setup] Applying power settings to SessionTrigger...
powershell -Command "$t = Get-ScheduledTask -TaskName 'SessionTrigger' -TaskPath '\ClaudeAutonomous\'; $t.Settings.DisallowStartIfOnBatteries = $false; $t.Settings.StopIfGoingOnBatteries = $false; Set-ScheduledTask -TaskName 'SessionTrigger' -TaskPath '\ClaudeAutonomous\' -Settings $t.Settings"

echo.
echo [setup] Done! Three tasks registered under ClaudeAutonomous\
echo   PCServer        — starts 30s after login  (port 3333)
echo   Bot             — starts 60s after login  (port 8080)
echo   SessionTrigger  — fires at hh:05 every hour
echo.
echo To start tasks immediately without rebooting:
echo   schtasks /Run /TN "ClaudeAutonomous\PCServer"
echo   schtasks /Run /TN "ClaudeAutonomous\Bot"
echo.
pause
