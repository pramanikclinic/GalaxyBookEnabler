@echo off
setlocal

echo ================================================================================
echo                    GALAXY BOOK ENABLER - LAUNCHER
echo ================================================================================
echo.

where pwsh.exe >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo Launching with PowerShell 7 [pwsh.exe]...
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-GalaxyBookEnabler.ps1" %*
    goto :end
)

if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    echo Launching with PowerShell 7 [Program Files]...
    "%ProgramFiles%\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-GalaxyBookEnabler.ps1" %*
    goto :end
)

if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" (
    echo Launching with PowerShell 7 [WindowsApps]...
    "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-GalaxyBookEnabler.ps1" %*
    goto :end
)

echo [!] ERROR: PowerShell 7 is required but was not found on your system.
echo     Windows PowerShell 5.1 (powershell.exe) is NOT compatible.
echo.
echo Would you like to install PowerShell 7 now via winget?
set /p INSTALL_CHOICE="Install PowerShell 7? (Y/N): "
if /i "%INSTALL_CHOICE%"=="Y" (
    echo Installing PowerShell 7...
    winget install Microsoft.PowerShell --accept-source-agreements --accept-package-agreements
    echo.
    echo Please restart this script after the installation finishes.
) else (
    echo Please install PowerShell 7 from: https://aka.ms/powershell
)
pause

:end
endlocal
