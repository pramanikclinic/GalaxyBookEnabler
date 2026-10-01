@echo off
setlocal
cd /d "%~dp0"

echo ================================================================================
echo             GALAXY BOOK DOLBY ATMOS ^& DOLBY ACCESS ENABLER
echo ================================================================================
echo.

where pwsh.exe >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo Launching with PowerShell 7 [pwsh.exe]...
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DolbyAtmosEnabler.ps1" %*
    goto :end
)

if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    echo Launching with PowerShell 7 [Program Files]...
    "%ProgramFiles%\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0DolbyAtmosEnabler.ps1" %*
    goto :end
)

if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" (
    echo Launching with PowerShell 7 [WindowsApps]...
    "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0DolbyAtmosEnabler.ps1" %*
    goto :end
)

echo Launching with Windows PowerShell [powershell.exe]...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DolbyAtmosEnabler.ps1" %*

:end
if %ERRORLEVEL% neq 0 (
    echo.
    echo Script ended with exit code %ERRORLEVEL%.
    pause
)
endlocal
