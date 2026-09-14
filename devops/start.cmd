@echo off
setlocal
REM ExecutionPolicy часто Restricted: cmd обходит его через Bypass только для этого запуска.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start.ps1" %*
exit /b %ERRORLEVEL%
