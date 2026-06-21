@echo off
REM ─────────────────────────────────────────────────────────────────────────
REM  start-pcserver.bat
REM  Starts PC Server with dynamic repo path derivation
REM ─────────────────────────────────────────────────────────────────────────

REM Derive REPO from script location: scripts\windows\start-pcserver.bat -> repo root
for %%I in ("%~dp0..\..") do set REPO=%%~fI

set PCSERVER_DIR=%REPO%\pc-server
set LOG_OUT=%REPO%\pc-server-out.log
set LOG_ERR=%REPO%\pc-server-err.log

echo [%date% %time%] Starting PC Server from %REPO% >> "%LOG_OUT%"

node "%PCSERVER_DIR%\dist\index.js" >> "%LOG_OUT%" 2>> "%LOG_ERR%"
