@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0hvigorw.ps1" %*
exit /b %ERRORLEVEL%
