@echo off
REM ─────────────────────────────────────────────────────────────────────────
REM  launch-pcserver.vbs wrapper
REM  Launches start-pcserver.bat hidden
REM ─────────────────────────────────────────────────────────────────────────

CreateObject("WScript.Shell").Run cmd /c "%~dp0start-pcserver.bat", 0, False
