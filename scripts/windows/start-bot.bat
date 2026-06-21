@echo off
REM ─────────────────────────────────────────────────────────────────────────
REM  start-bot.bat
REM  Starts Telegram Bot with dynamic repo path derivation
REM ─────────────────────────────────────────────────────────────────────────

REM Derive REPO from script location: scripts\windows\start-bot.bat -> repo root
for %%I in ("%~dp0..\..") do set REPO=%%~fI

set BOT_DIR=%REPO%\bot
set LOG_OUT=%REPO%\bot-out.log
set LOG_ERR=%REPO%\bot-err.log

echo [%date% %time%] Starting Bot from %REPO% >> "%LOG_OUT%"

node "%BOT_DIR%\dist\index.js" >> "%LOG_OUT%" 2>> "%LOG_ERR%"
