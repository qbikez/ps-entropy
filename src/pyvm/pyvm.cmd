@echo off

(echo REM pyvm.cmd) > "%TEMP%\_env.cmd"
powershell %~dp0\pyvm.ps1 %*

call "%TEMP%\_env.cmd"