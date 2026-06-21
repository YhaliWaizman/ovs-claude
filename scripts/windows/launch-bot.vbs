REM ─────────────────────────────────────────────────────────────────────────
REM  launch-bot.vbs wrapper
REM  Launches start-bot.bat hidden
REM ─────────────────────────────────────────────────────────────────────────

CreateObject("WScript.Shell").Run cmd /c "%~dp0start-bot.bat", 0, False
