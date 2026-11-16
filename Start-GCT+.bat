@echo off
REM DOC: docs/ARCHITECTURE.md#inicializacao
setlocal
set "SCRIPT=%~dp0GCT+.ps1"
powershell.exe -NoLogo -NoProfile -STA -File "%SCRIPT%"
if errorlevel 1 (
    echo.
    echo GCT+ encerrou com erro. Consulte a mensagem acima.
    pause
)
