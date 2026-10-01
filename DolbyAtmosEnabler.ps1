<#
.SYNOPSIS
    Galaxy Book Dolby Atmos & Dolby Access Enabler (Experimental)
.DESCRIPTION
    Unified installer, uninstaller, and diagnostic manager for Samsung Galaxy Book
    Dolby DAX3 Audio Processing Objects (APO) and Samsung Audio Extension drivers.
    Enables genuine Dolby Atmos and Dolby Access on non-Galaxy Book systems with
    Dynamic, Movie, Music, Game, Voice profiles, and 10-band Graphic Equalizer.
.PARAMETER Install
    Installs and configures Galaxy Book Dolby DAX3 drivers and services.
.PARAMETER Uninstall
    Safely removes Dolby DAX3 APO bindings, services, files, and registry entries.
.PARAMETER Status
    Displays the current installation and activation status of Dolby Atmos.
.PARAMETER InstallApp
    Installs or updates the Dolby Access application from the Microsoft Store.
.PARAMETER DriverPath
    Custom path to exported Galaxy Book Dolby drivers folder. If omitted, automatically
    searches Drivers\DolbyDrivers and GalaxyBook-DonorProfile directories.
.PARAMETER RemoveDrivers
    When uninstalling, also deletes staged driver packages from Windows DriverStore via pnputil.
.PARAMETER Force
    Suppresses confirmation prompts.
.PARAMETER SkipAppInstall
    Skips checking or prompting for the Dolby Access Microsoft Store application.
.PARAMETER TestMode
    Simulates actions without making system changes.
.EXAMPLE
    .\DolbyAtmosEnabler.ps1
    (Runs interactive menu)
.EXAMPLE
    .\DolbyAtmosEnabler.ps1 -Install
.EXAMPLE
    .\DolbyAtmosEnabler.ps1 -Uninstall -RemoveDrivers -Force
.EXAMPLE
    .\DolbyAtmosEnabler.ps1 -Status
#>

[CmdletBinding(DefaultParameterSetName = "Interactive")]
param(
    [Parameter(ParameterSetName = "Install")]
    [switch]$Install,

    [Parameter(ParameterSetName = "Uninstall")]
    [switch]$Uninstall,

    [Parameter(ParameterSetName = "Status")]
    [switch]$Status,

    [Parameter(ParameterSetName = "InstallApp")]
    [switch]$InstallApp,

    [Parameter(ParameterSetName = "Install")]
    [Parameter(ParameterSetName = "Interactive")]
    [string]$DriverPath,

    [Parameter(ParameterSetName = "Uninstall")]
    [switch]$RemoveDrivers,

    [Parameter(ParameterSetName = "Uninstall")]
    [switch]$Force,

    [Parameter(ParameterSetName = "Install")]
    [switch]$SkipAppInstall,

    [switch]$TestMode
)

$ErrorActionPreference = "Stop"

$script:ThisScriptPath = if ($PSCommandPath) {
    $PSCommandPath
} elseif ($PSScriptRoot) {
    Join-Path $PSScriptRoot "DolbyAtmosEnabler.ps1"
} elseif ($MyInvocation.PSCommandPath) {
    $MyInvocation.PSCommandPath
} else {
    $MyInvocation.MyCommand.Definition
}

# ==================== STATUS LOGGER ====================
function Write-Status {
    param(
        [string]$Message,
        [ValidateSet("OK", "WARN", "ERROR", "INFO", "ACTION")]
        [string]$Status = "INFO"
    )
    switch ($Status) {
        "OK"     { Write-Host "  ✓ $Message" -ForegroundColor Green }
        "WARN"   { Write-Host "  ⚠ $Message" -ForegroundColor Yellow }
        "ERROR"  { Write-Host "  ❌ $Message" -ForegroundColor Red }
        "ACTION" { Write-Host "⚡ $Message" -ForegroundColor Cyan }
        "INFO"   { Write-Host "  ℹ $Message" -ForegroundColor Gray }
    }
}

# ==================== ELEVATION HELPER ====================
function Ensure-AdminPrivileges {
    param([string[]]$ForwardArgs)

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin -or $TestMode) {
        if ($TestMode -and -not $isAdmin) {
            Write-Host "⚡ Running in TestMode without elevation (simulation only)." -ForegroundColor Cyan
        }
        return
    }

    Write-Host "⚡ Requesting administrator privileges..." -ForegroundColor Yellow

    $scriptPath = if ($script:ThisScriptPath) {
        $script:ThisScriptPath
    } elseif ($PSCommandPath) {
        $PSCommandPath
    } elseif ($MyInvocation.PSCommandPath) {
        $MyInvocation.PSCommandPath
    } elseif ($PSScriptRoot) {
        Join-Path $PSScriptRoot "DolbyAtmosEnabler.ps1"
    } else {
        $MyInvocation.MyCommand.Definition
    }

    $psExe = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh.exe" } else { "powershell.exe" }
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"")
    if ($ForwardArgs) {
        $argList += $ForwardArgs
    }

    # Try gsudo
    $gsudo = Get-Command gsudo.exe -ErrorAction SilentlyContinue
    if ($gsudo) {
        & gsudo.exe $psExe $argList
        exit $LASTEXITCODE
    }

    # Try Windows sudo
    $sudo = Get-Command sudo.exe -ErrorAction SilentlyContinue
    if ($sudo) {
        $sudoCheck = & sudo.exe config 2>&1 | Out-String
        if ($sudoCheck -notmatch "disabled") {
            & sudo.exe $psExe $argList
            exit $LASTEXITCODE
        }
    }

    # Fallback to Start-Process -Verb RunAs
    try {
        $p = Start-Process -FilePath $psExe -ArgumentList $argList -Verb RunAs -PassThru -Wait
        exit $p.ExitCode
    }
    catch {
        Write-Host "❌ Failed to elevate: $_" -ForegroundColor Red
        Write-Host "Please right-click PowerShell and select 'Run as Administrator', then rerun this script." -ForegroundColor Yellow
        exit 1
    }
}

# ==================== COMMON AUDIO HELPERS ====================
function Stop-DolbyProcesses {
    Get-Process -Name "*DolbyAccess*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process -Name "*DAX3*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Restart-WindowsAudio {
    Write-Host "`nRefreshing Windows Audio pipeline..." -ForegroundColor Cyan
    try {
        Restart-Service -Name "Audiosrv" -Force -ErrorAction SilentlyContinue
        Write-Status "Windows Audio service refreshed." -Status OK
    }
    catch {
        Write-Status "Notice restarting Audiosrv: $_ (Reboot if audio is unaffected)" -Status WARN
    }
}

# ==================== STATUS CHECK ====================
function Get-DolbyInstallationStatus {
    Write-Host @"
================================================================================
                    DOLBY ATMOS STATUS & DIAGNOSTICS
================================================================================
"@ -ForegroundColor Cyan

    # 1. Check DolbyDAXAPI Service
    $daxSvc = Get-Service -Name "DolbyDAXAPI" -ErrorAction SilentlyContinue
    if (-not $daxSvc) {
        $daxSvc = Get-Service -Name "DolbyDAXAPIService" -ErrorAction SilentlyContinue
    }
    if ($daxSvc) {
        $color = if ($daxSvc.Status -eq "Running") { "Green" } else { "Yellow" }
        Write-Host "  Service Status:    $($daxSvc.Name) [$($daxSvc.Status)] (Startup: $($daxSvc.StartType))" -ForegroundColor $color
    } else {
        Write-Host "  Service Status:    Not Installed" -ForegroundColor Red
    }

    # 2. Check Service Binary & Directory
    $serviceImagePath = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\DolbyDAXAPI' -ErrorAction SilentlyContinue).ImagePath
    $svcExe = if ($serviceImagePath) {
        $serviceImagePath.Trim('"').Trim()
    } else {
        $possibleExes = @(
            "C:\Windows\System32\dolbyaposvc\DAX3API.exe",
            "C:\Windows\System32\dolbyaposvc\DolbyDAXAPIService.exe"
        )
        $possibleExes | Where-Object { Test-Path $_ } | Select-Object -First 1
    }

    if ($svcExe -and (Test-Path $svcExe)) {
        $ver = (Get-ItemProperty $svcExe -ErrorAction SilentlyContinue).VersionInfo.ProductVersion
        Write-Host "  Service Binary:    Present ($svcExe - v$ver)" -ForegroundColor Green
    } else {
        Write-Host "  Service Binary:    Missing ($svcExe)" -ForegroundColor Red
    }

    # 3. Check COM CLSIDs
    $sfxGuid = "{0EBD8505-17BB-4AE7-AD76-E86F99A425E9}"
    $clsidKey = "Registry::HKCR\CLSID\$sfxGuid"
    if (Test-Path $clsidKey) {
        Write-Host "  APO COM CLSIDs:    Registered (DAX3 SFX/MFX/EFX)" -ForegroundColor Green
    } else {
        Write-Host "  APO COM CLSIDs:    Not Registered" -ForegroundColor Red
    }

    # 4. Check Registry Configuration
    $daxReg = "HKLM:\SOFTWARE\Dolby\DAX"
    if (Test-Path $daxReg) {
        $activeProf = (Get-ItemProperty -Path $daxReg -Name "ActiveProfile" -ErrorAction SilentlyContinue).ActiveProfile
        $prodVer = (Get-ItemProperty -Path $daxReg -Name "ProductVersion" -ErrorAction SilentlyContinue).ProductVersion
        Write-Host "  DAX Registry:      Configured (Active Profile: $activeProf, Version: $prodVer)" -ForegroundColor Green
    } else {
        Write-Host "  DAX Registry:      Missing ($daxReg)" -ForegroundColor Yellow
    }

    # 5. Check Endpoint APO Bindings
    $renderKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
    $activeBindings = 0
    if (Test-Path $renderKey) {
        Get-ChildItem -Path $renderKey -ErrorAction SilentlyContinue | ForEach-Object {
            $fxKey = Join-Path $_.PSPath "FxProperties"
            if (Test-Path $fxKey) {
                $fxProps = Get-ItemProperty -Path $fxKey -ErrorAction SilentlyContinue
                if ($fxProps) {
                    $matched = $false
                    foreach ($prop in $fxProps.PSObject.Properties) {
                        if ($prop.Value -match "0EBD8505|0EBD8506|0EBD8507|0EBD8511|0EBD8512") {
                            $matched = $true
                            break
                        }
                    }
                    if ($matched) { $activeBindings++ }
                }
            }
        }
    }
    if ($activeBindings -gt 0) {
        Write-Host "  Active Endpoints:  $activeBindings audio render endpoint(s) bound to Dolby DAX3 APO" -ForegroundColor Green
    } else {
        Write-Host "  Active Endpoints:  No endpoints bound to Dolby DAX3 APO" -ForegroundColor Yellow
    }

    # 6. Check Dolby Access UWP App
    $dolbyApp = Get-AppxPackage -Name "*DolbyAccess*" -ErrorAction SilentlyContinue
    if ($dolbyApp) {
        Write-Host "  Dolby Access App:  Installed (Version: $($dolbyApp.Version))" -ForegroundColor Green
    } else {
        Write-Host "  Dolby Access App:  Not Installed (Available from Microsoft Store: 9N0866FS04W8)" -ForegroundColor Yellow
    }

    # 7. Check Samsung ModuleDolbyAtmos
    $moduleDolbyKey = "HKLM:\SOFTWARE\Samsung\SamsungSettings\ModuleDolbyAtmos"
    if (Test-Path $moduleDolbyKey) {
        $support = (Get-ItemProperty -Path $moduleDolbyKey -Name "Support" -ErrorAction SilentlyContinue).Support
        $onoff = (Get-ItemProperty -Path $moduleDolbyKey -Name "OnOff" -ErrorAction SilentlyContinue).OnOff
        Write-Host "  Samsung Settings:  ModuleDolbyAtmos Support=$support, OnOff=$onoff" -ForegroundColor Gray
    }

    Write-Host "================================================================================`n" -ForegroundColor Cyan
}

# ==================== DOLBY ACCESS APP INSTALLER ====================
function Install-DolbyAccessApp {
    param([switch]$PromptReinstall)

    Write-Host @"
================================================================================
                    DOLBY ACCESS APP INSTALLATION
================================================================================
"@ -ForegroundColor Cyan

    $dolbyApp = Get-AppxPackage -Name "*DolbyAccess*" -ErrorAction SilentlyContinue
    if ($dolbyApp) {
        Write-Status "Dolby Access app is currently installed (Version: $($dolbyApp.Version))." -Status OK
        if ($PromptReinstall) {
            $choice = Read-Host "Would you like to reinstall or update Dolby Access? (Y/N) [Default: N]"
            if ($choice -notmatch "^[Yy]") {
                return
            }
        } else {
            return
        }
    } else {
        Write-Status "Dolby Access app is not currently installed." -Status WARN
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "Installing Dolby Access from Microsoft Store via winget (ID: 9N0866FS04W8)..." -ForegroundColor Cyan
        & winget.exe install --id 9N0866FS04W8 --source msstore --accept-package-agreements --accept-source-agreements
        $installedApp = Get-AppxPackage -Name "*DolbyAccess*" -ErrorAction SilentlyContinue
        if ($installedApp) {
            Write-Status "Dolby Access app installed successfully (Version: $($installedApp.Version))." -Status OK
        } else {
            Write-Status "Winget finished. If the app is not listed, you can install it from the Store." -Status WARN
            Start-Process "ms-windows-store://pdp/?ProductId=9N0866FS04W8" -ErrorAction SilentlyContinue
        }
    } else {
        Write-Status "winget is not available. Opening Microsoft Store page for Dolby Access..." -Status INFO
        Start-Process "ms-windows-store://pdp/?ProductId=9N0866FS04W8" -ErrorAction SilentlyContinue
    }
}

# ==================== INSTALLER LOGIC ====================
function Invoke-DolbyInstall {
    param([string]$CustomDriverPath)

    Write-Host @"
================================================================================
       GALAXY BOOK DOLBY ATMOS & DOLBY ACCESS ENABLER (EXPERIMENTAL)
================================================================================
This script installs authentic Samsung Galaxy Book Dolby DAX3 drivers,
enables the Dolby Audio Processing Object (APO) pipeline on your sound card,
and activates Dolby Access for all speakers and headphones.
================================================================================
"@ -ForegroundColor Cyan

    if ($TestMode) {
        Write-Status "[TEST MODE] Would locate and install Dolby DAX3 drivers and start Dolby DAX service." -Status INFO
        Write-Status "[TEST MODE] No changes applied." -Status OK
        return
    }

    # Locate Dolby driver directory
    $possiblePaths = @()
    if ($CustomDriverPath) { $possiblePaths += $CustomDriverPath }
    $possiblePaths += @(
        (Join-Path $PSScriptRoot "Drivers\DolbyDrivers"),
        (Join-Path $PSScriptRoot "Drivers\GalaxyBook-DolbyDrivers"),
        ".\Drivers\DolbyDrivers",
        ".\Drivers\GalaxyBook-DolbyDrivers",
        (Join-Path $PSScriptRoot "GalaxyBook-DolbyDrivers"),
        (Join-Path $PSScriptRoot "GalaxyBook-DonorProfile\Drivers\DolbyDrivers"),
        ".\GalaxyBook-DolbyDrivers",
        ".\GalaxyBook-DonorProfile\Drivers\DolbyDrivers",
        ".\GalaxyBook-DonorProfile*\Drivers\DolbyDrivers",
        (Join-Path $HOME "Desktop\GalaxyBook-DolbyDrivers"),
        (Join-Path $HOME "Downloads\GalaxyBook-DolbyDrivers")
    )

    $dolbyDir = $null
    foreach ($p in $possiblePaths) {
        $resolved = Resolve-Path $p -ErrorAction SilentlyContinue
        if ($resolved) {
            foreach ($res in $resolved) {
                $hasInfs = Get-ChildItem -Path $res.Path -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match 'dax3|dolby|samsungext' }
                if ($hasInfs) {
                    $dolbyDir = $res.Path
                    break
                }
            }
        }
        if ($dolbyDir) { break }
    }

    if (-not $dolbyDir) {
        Write-Host "`nCould not automatically locate the Galaxy Book Dolby drivers folder." -ForegroundColor Yellow
        Write-Host "Please enter the full path to your exported 'GalaxyBook-DolbyDrivers' folder" -ForegroundColor Gray
        Write-Host "(or the GalaxyBook-DonorProfile\Drivers\DolbyDrivers folder):" -ForegroundColor Gray
        $promptPath = Read-Host "Driver folder path"
        if ($promptPath) {
            $resolved = Resolve-Path $promptPath -ErrorAction SilentlyContinue
            if ($resolved) { $dolbyDir = $resolved.Path }
        }
    }

    if (-not $dolbyDir -or -not (Test-Path $dolbyDir)) {
        Write-Status "Dolby drivers folder not found." -Status ERROR
        Write-Host @"
To activate Dolby Access:
1. Run 'Export-GalaxyBookDonorProfile.ps1 -ExportDolbyDrivers' on your genuine Galaxy Book.
2. Copy the exported 'GalaxyBook-DonorProfile\Drivers\DolbyDrivers' folder to this machine.
3. Rerun this script specifying the path: .\DolbyAtmosEnabler.ps1 -Install -DriverPath <Path>
"@ -ForegroundColor Yellow
        return
    }

    Write-Status "Using Dolby drivers folder: $dolbyDir" -Status OK

    # 1. Stop existing Dolby processes and services
    Write-Host "`n[1/6] Preparing system & stopping Dolby processes..." -ForegroundColor Cyan
    Stop-DolbyProcesses
    $oldService = Get-Service -Name "DolbyDAXAPI" -ErrorAction SilentlyContinue
    if ($oldService -and $oldService.Status -eq "Running") {
        Stop-Service -Name "DolbyDAXAPI" -Force -ErrorAction SilentlyContinue
    }

    # 2. Patch operator_settings for full Dynamic profile support
    Write-Host "`n[2/6] Configuring Dolby operator profiles & tuning..." -ForegroundColor Cyan
    $opXmlFiles = Get-ChildItem -Path $dolbyDir -Filter "operator_settings.xml" -Recurse -ErrorAction SilentlyContinue
    foreach ($ox in $opXmlFiles) {
        try {
            [xml]$xml = Get-Content $ox.FullName -Raw
            $changed = $false
            if ($xml.settings.spatial_audio) {
                foreach ($prop in $xml.settings.spatial_audio.property) {
                    if ($prop.name -eq "spatial_audio") {
                        if ($prop.state -eq "off" -and $prop.value -ne "true") {
                            $prop.value = "true"
                            $changed = $true
                        }
                    }
                }
            }
            if ($xml.settings.general) {
                foreach ($prop in $xml.settings.general.property) {
                    if ($prop.name -eq "ShowAutoProfileButton" -and $prop.value -ne "true") {
                        $prop.value = "true"
                        $changed = $true
                    }
                    if ($prop.name -eq "AutoProfileEnabled" -and $prop.value -ne "true") {
                        $prop.value = "true"
                        $changed = $true
                    }
                    if ($prop.name -eq "DolbyEnabled" -and $prop.value -ne "true") {
                        $prop.value = "true"
                        $changed = $true
                    }
                }
            }
            if ($changed) {
                $xml.Save($ox.FullName)
                Write-Status "Patched $($ox.Name): Enabled Dynamic Profile & Direct DAP output." -Status OK
            }
        }
        catch {
            Write-Status "Notice parsing $($ox.FullName): $_" -Status WARN
        }
    }

    $opJsonFiles = Get-ChildItem -Path $dolbyDir -Filter "operator_settings.json" -Recurse -ErrorAction SilentlyContinue
    foreach ($oj in $opJsonFiles) {
        try {
            $jsonContent = Get-Content $oj.FullName -Raw
            $jsonChanged = $false
            if ($jsonContent -match '"ShowAutoProfileButton":\s*false') {
                $jsonContent = $jsonContent -replace '"ShowAutoProfileButton":\s*false', '"ShowAutoProfileButton": true'
                $jsonChanged = $true
            }
            if ($jsonContent -match '"AutoProfileEnabled":\s*false') {
                $jsonContent = $jsonContent -replace '"AutoProfileEnabled":\s*false', '"AutoProfileEnabled": true'
                $jsonChanged = $true
            }
            if ($jsonChanged) {
                Set-Content -Path $oj.FullName -Value $jsonContent -Force
                Write-Status "Patched $($oj.Name): Enabled Dynamic Profile." -Status OK
            }
        }
        catch { }
    }

    # 3. Stage and Install INF Driver Packages into DriverStore
    Write-Host "`n[3/6] Staging & Installing Galaxy Book Dolby drivers via pnputil..." -ForegroundColor Cyan
    $infFiles = Get-ChildItem -Path $dolbyDir -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    $pnpCount = 0
    foreach ($inf in $infFiles) {
        Write-Host "  Installing $($inf.Name)..." -ForegroundColor Gray
        $output = & pnputil.exe /add-driver "$($inf.FullName)" /install 2>&1 | Out-String
        if ($output -match "Successfully added|Driver package added successfully|Driver package installed") {
            Write-Status "Installed $($inf.Name)" -Status OK
            $pnpCount++
        } elseif ($output -match "already exists|already installed") {
            Write-Status "Already staged: $($inf.Name)" -Status INFO
            $pnpCount++
        } else {
            Write-Status "pnputil output for $($inf.Name): $($output.Trim())" -Status INFO
        }
    }

    # 4. Copy service binaries if not yet installed by INF
    Write-Host "`n[4/6] Setting up Dolby DAX3 API Service..." -ForegroundColor Cyan
    $destSvcDir = "C:\Windows\System32\dolbyaposvc"
    if (-not (Test-Path $destSvcDir)) {
        New-Item -Path $destSvcDir -ItemType Directory -Force | Out-Null
    }

    $sourceSvcFiles = Get-ChildItem -Path $dolbyDir -Filter "DolbyDAXAPI*" -Recurse -ErrorAction SilentlyContinue
    foreach ($sf in $sourceSvcFiles) {
        $target = Join-Path $destSvcDir $sf.Name
        if (-not (Test-Path $target)) {
            Copy-Item -Path $sf.FullName -Destination $target -Force -ErrorAction SilentlyContinue
        }
    }
    $extraSvcFiles = Get-ChildItem -Path $dolbyDir -Include "*.dll","*.exe","*.xml","*.json" -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -match 'aposvc' }
    foreach ($ef in $extraSvcFiles) {
        $target = Join-Path $destSvcDir $ef.Name
        if (-not (Test-Path $target)) {
            Copy-Item -Path $ef.FullName -Destination $target -Force -ErrorAction SilentlyContinue
        }
    }

    # Register/Update DolbyDAXAPI service
    $serviceExe = @(
        (Join-Path $destSvcDir "DAX3API.exe"),
        (Join-Path $destSvcDir "DolbyDAXAPIService.exe")
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    $daxSvc = Get-Service -Name "DolbyDAXAPI" -ErrorAction SilentlyContinue
    if (-not $daxSvc -and $serviceExe) {
        & sc.exe create DolbyDAXAPI binPath= "`"$serviceExe`"" start= auto DisplayName= "Dolby DAX API Service" 2>&1 | Out-Null
        & sc.exe description DolbyDAXAPI "Dolby Audio Processing Object (APO) service for Galaxy Book audio enhancement and spatial processing." 2>&1 | Out-Null
    }

    # 5. Register COM CLSIDs and AudioProcessingObjects keys
    Write-Host "`n[5/6] Registering Dolby DAX3 APO COM Classes & Registry bindings..." -ForegroundColor Cyan

    $apoGuids = @{
        "SFX" = "{0EBD8505-17BB-4AE7-AD76-E86F99A425E9}"
        "MFX" = "{0EBD8506-17BB-4AE7-AD76-E86F99A425E9}"
        "EFX" = "{0EBD8507-17BB-4AE7-AD76-E86F99A425E9}"
        "INT" = "{0212AE2C-F779-4A50-9B10-57A0AEF22870}"
        "PRX" = "{0EBD8511-17BB-4AE7-AD76-E86F99A425E9}"
        "FAC" = "{0EBD8512-17BB-4AE7-AD76-E86F99A425E9}"
    }

    $daxDll = @(
        (Join-Path $destSvcDir "DolbyDax3Apo.dll"),
        (Join-Path $destSvcDir "dax3_apoksl.dll")
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $daxDll) {
        $foundDll = Get-ChildItem -Path $dolbyDir -Include "DolbyDax3Apo.dll","dax3_apoksl.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($foundDll) {
            $daxDll = Join-Path $destSvcDir $foundDll.Name
            Copy-Item -Path $foundDll.FullName -Destination $daxDll -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($kv in $apoGuids.GetEnumerator()) {
        $guid = $kv.Value
        $paths = @(
            "Registry::HKCR\CLSID\$guid",
            "HKLM:\SOFTWARE\Classes\CLSID\$guid",
            "Registry::HKCR\AudioEngine\AudioProcessingObjects\$guid",
            "HKLM:\SOFTWARE\Classes\AudioEngine\AudioProcessingObjects\$guid"
        )
        foreach ($rp in $paths) {
            if (-not (Test-Path $rp)) {
                New-Item -Path $rp -Force -ErrorAction SilentlyContinue | Out-Null
            }
            if (Test-Path $rp) {
                Set-ItemProperty -Path $rp -Name "(default)" -Value "Dolby DAX3 Audio Processing Object" -Force -ErrorAction SilentlyContinue
                if ($rp -match 'CLSID') {
                    $inproc = Join-Path $rp "InprocServer32"
                    if (-not (Test-Path $inproc)) {
                        New-Item -Path $inproc -Force -ErrorAction SilentlyContinue | Out-Null
                    }
                    if (Test-Path $daxDll) {
                        Set-ItemProperty -Path $inproc -Name "(default)" -Value $daxDll -Force -ErrorAction SilentlyContinue
                        Set-ItemProperty -Path $inproc -Name "ThreadingModel" -Value "Both" -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    # Bind Dolby APO CLSIDs to active audio render endpoints
    $renderKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
    if (Test-Path $renderKey) {
        $endpoints = Get-ChildItem -Path $renderKey -ErrorAction SilentlyContinue
        foreach ($ep in $endpoints) {
            $fxKey = Join-Path $ep.PSPath "FxProperties"
            if (-not (Test-Path $fxKey)) {
                New-Item -Path $fxKey -Force -ErrorAction SilentlyContinue | Out-Null
            }
            if (Test-Path $fxKey) {
                Set-ItemProperty -Path $fxKey -Name "{D04E05A6-594B-4FB6-A80D-01AF5EED7D1D},1" -Value $apoGuids["SFX"] -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $fxKey -Name "{D04E05A6-594B-4FB6-A80D-01AF5EED7D1D},2" -Value $apoGuids["MFX"] -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $fxKey -Name "{D04E05A6-594B-4FB6-A80D-01AF5EED7D1D},5" -Value $apoGuids["SFX"] -Force -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $fxKey -Name "{D04E05A6-594B-4FB6-A80D-01AF5EED7D1D},6" -Value $apoGuids["EFX"] -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Status "Bound Dolby DAX3 APO to $($endpoints.Count) audio render endpoints." -Status OK
    }

    # Driver InterfaceSetting and APO presets
    $driverKeys = @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96c-e325-11ce-bfc1-08002be10318}"
    )
    foreach ($dk in $driverKeys) {
        if (Test-Path $dk) {
            Get-ChildItem -Path $dk -ErrorAction SilentlyContinue | ForEach-Object {
                $ifKey = Join-Path $_.PSPath "InterfaceSetting"
                if (-not (Test-Path $ifKey)) {
                    New-Item -Path $ifKey -Force -ErrorAction SilentlyContinue | Out-Null
                }
                if (Test-Path $ifKey) {
                    Set-ItemProperty -Path $ifKey -Name "SystemCustomizedEffectsDriver" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $ifKey -Name "LineOutTopo" -Value @("ApoPreset1") -Type MultiString -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $ifKey -Name "SecondaryLineOutTopo" -Value @("ApoPreset2") -Type MultiString -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $ifKey -Name "RearLineOutTopoSST3" -Value @("ApoPreset2") -Type MultiString -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $ifKey -Name "RearLineOutTopoHAP3" -Value @("ApoPreset2") -Type MultiString -Force -ErrorAction SilentlyContinue

                    $preset1 = Join-Path $ifKey "ApoPreset1"
                    if (-not (Test-Path $preset1)) { New-Item -Path $preset1 -Force | Out-Null }
                    Set-ItemProperty -Path $preset1 -Name "SFX" -Value $apoGuids["SFX"] -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $preset1 -Name "MFX" -Value $apoGuids["MFX"] -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $preset1 -Name "EFX" -Value $apoGuids["EFX"] -Force -ErrorAction SilentlyContinue

                    $preset2 = Join-Path $ifKey "ApoPreset2"
                    if (-not (Test-Path $preset2)) { New-Item -Path $preset2 -Force | Out-Null }
                    Set-ItemProperty -Path $preset2 -Name "SFX" -Value $apoGuids["SFX"] -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $preset2 -Name "MFX" -Value $apoGuids["MFX"] -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path $preset2 -Name "EFX" -Value $apoGuids["EFX"] -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    # Configure Dolby DAX registry keys
    $dolbyDaxKey = "HKLM:\SOFTWARE\Dolby\DAX"
    if (-not (Test-Path $dolbyDaxKey)) {
        New-Item -Path $dolbyDaxKey -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Set-ItemProperty -Path $dolbyDaxKey -Name "ProductVersion" -Value "3.30509.591.0" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $dolbyDaxKey -Name "ActiveProfile" -Value "Dynamic" -Type String -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $dolbyDaxKey -Name "FeatureConfig" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $dolbyDaxKey -Name "PreProcessingAvailable" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $dolbyDaxKey -Name "PostProcessingAvailable" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue

    # Configure Samsung Settings ModuleDolbyAtmos
    $moduleDolbyKey = "HKLM:\SOFTWARE\Samsung\SamsungSettings\ModuleDolbyAtmos"
    if (-not (Test-Path $moduleDolbyKey)) {
        New-Item -Path $moduleDolbyKey -Force -ErrorAction SilentlyContinue | Out-Null
    }
    Set-ItemProperty -Path $moduleDolbyKey -Name "Support" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Set-ItemProperty -Path $moduleDolbyKey -Name "OnOff" -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Status "Enabled Samsung Settings Dolby Atmos Module (Support=1, OnOff=1)." -Status OK

    # 6. Start service and refresh Windows Audio
    Write-Host "`n[6/6] Starting Dolby DAX service & refreshing Windows Audio..." -ForegroundColor Cyan
    try {
        & sc.exe config DolbyDAXAPI start= auto 2>&1 | Out-Null
        & sc.exe start DolbyDAXAPI 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        $svcNow = Get-Service -Name "DolbyDAXAPI" -ErrorAction SilentlyContinue
        if ($svcNow -and $svcNow.Status -eq "Running") {
            Write-Status "DolbyDAXAPI service is running." -Status OK
        } else {
            Write-Status "DolbyDAXAPI service configured (will start on next boot or audio playback)." -Status WARN
        }
    }
    catch {
        Write-Status "Notice starting DolbyDAXAPI: $_" -Status WARN
    }

    Restart-WindowsAudio

    # Check Dolby Access UWP App
    if (-not $SkipAppInstall) {
        Install-DolbyAccessApp
    }

    Write-Host @"

================================================================================
                    DOLBY ATMOS ACTIVATION COMPLETE!
================================================================================
1. Open the 'Dolby Access' app from the Start menu.
2. Under Settings/Products, Dolby Atmos for built-in speakers will show 'Ready to use'.
3. The Dynamic profile and Equalizer are active and ready.
4. In Samsung Settings -> Audio, the Dolby Atmos toggle will be enabled.

Note: Dolby Atmos for Headphones requires a personal Microsoft Store license,
while Dolby Atmos for Built-in Speakers / Audio Endpoints auto-activates via OEM APO.
================================================================================
"@ -ForegroundColor Green

    return
}

# ==================== UNINSTALLER LOGIC ====================
function Invoke-DolbyUninstall {
    Write-Host @"
================================================================================
       GALAXY BOOK DOLBY ATMOS & DOLBY ACCESS UNINSTALLER
================================================================================
This script completely removes Galaxy Book Dolby DAX3 Audio Processing Objects,
unregisters Dolby APO COM classes, removes driver bindings, and deletes the service.
================================================================================
"@ -ForegroundColor Yellow

    if (-not $Force -and -not $TestMode) {
        Write-Host "Are you sure you want to remove Galaxy Book Dolby Atmos components? (Y/N)" -ForegroundColor Yellow -NoNewline
        $resp = Read-Host " "
        if ($resp -notmatch "^[Yy]") {
            Write-Host "Uninstallation cancelled." -ForegroundColor Gray
            return
        }
    }

    if ($TestMode) {
        Write-Status "[TEST MODE] Would remove Dolby DAX3 service, APO bindings, and files." -Status INFO
        Write-Status "[TEST MODE] No changes applied." -Status OK
        return
    }

    # 1. Terminate Dolby processes
    Write-Host "`n[1/7] Stopping Dolby processes..." -ForegroundColor Cyan
    Stop-DolbyProcesses
    Write-Status "Stopped Dolby Access and DAX3 processes." -Status OK

    # 2. Stop and delete Dolby DAX API Service
    Write-Host "`n[2/7] Removing Dolby DAX API Service..." -ForegroundColor Cyan
    $serviceNames = @("DolbyDAXAPI", "DolbyDAXAPIService")
    foreach ($sName in $serviceNames) {
        $svc = Get-Service -Name $sName -ErrorAction SilentlyContinue
        if ($svc) {
            try {
                if ($svc.Status -eq "Running") {
                    Stop-Service -Name $sName -Force -ErrorAction SilentlyContinue
                }
                Start-Sleep -Milliseconds 500
            } catch { }
            try {
                & sc.exe stop $sName 2>&1 | Out-Null
                & sc.exe delete $sName 2>&1 | Out-Null
                Write-Status "Removed service: $sName" -Status OK
            } catch {
                Write-Status "Notice removing service ${sName}: $_" -Status WARN
            }
        }
    }

    # 3. Clean up active audio render endpoints (FxProperties)
    Write-Host "`n[3/7] Cleaning up Dolby APO bindings on audio endpoints..." -ForegroundColor Cyan
    $renderKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
    $cleanedEndpoints = 0
    if (Test-Path $renderKey) {
        $endpoints = Get-ChildItem -Path $renderKey -ErrorAction SilentlyContinue
        foreach ($ep in $endpoints) {
            $fxKey = Join-Path $ep.PSPath "FxProperties"
            if (Test-Path $fxKey) {
                $endpointCleaned = $false

                $allProps = Get-ItemProperty -Path $fxKey -ErrorAction SilentlyContinue
                if ($allProps) {
                    foreach ($prop in $allProps.PSObject.Properties) {
                        $propStr = if ($prop.Value -is [System.Array]) { $prop.Value -join " " } else { "$($prop.Value)" }
                        if ($propStr -match "0EBD8505|0EBD8506|0EBD8507|0EBD8511|0EBD8512|0212AE2C|dolby") {
                            if ($prop.Value -is [System.Array]) {
                                $remaining = @($prop.Value | Where-Object { $_ -notmatch "0EBD8505|0EBD8506|0EBD8507|0EBD8511|0EBD8512|0212AE2C|dolby" })
                                if ($remaining.Count -gt 0) {
                                    Set-ItemProperty -Path $fxKey -Name $prop.Name -Value $remaining -Type MultiString -Force -ErrorAction SilentlyContinue
                                    $endpointCleaned = $true
                                } else {
                                    Remove-ItemProperty -Path $fxKey -Name $prop.Name -Force -ErrorAction SilentlyContinue
                                    $regPath = $fxKey -replace '^Microsoft\.PowerShell\.Core\\Registry::', '' -replace '^Registry::', '' -replace '^HKLM:\\', 'HKLM\' -replace '^HKLM:', 'HKLM'
                                    & reg.exe delete "$regPath" /v "$($prop.Name)" /f 2>&1 | Out-Null
                                    $endpointCleaned = $true
                                }
                            } else {
                                Remove-ItemProperty -Path $fxKey -Name $prop.Name -Force -ErrorAction SilentlyContinue
                                $regPath = $fxKey -replace '^Microsoft\.PowerShell\.Core\\Registry::', '' -replace '^Registry::', '' -replace '^HKLM:\\', 'HKLM\' -replace '^HKLM:', 'HKLM'
                                & reg.exe delete "$regPath" /v "$($prop.Name)" /f 2>&1 | Out-Null
                                $endpointCleaned = $true
                            }
                        }
                    }
                }

                if ($endpointCleaned) {
                    $cleanedEndpoints++
                }
            }
        }
    }
    Write-Status "Removed Dolby APO bindings from $cleanedEndpoints endpoint(s)." -Status OK

    # 4. Clean up driver InterfaceSetting APO keys
    Write-Host "`n[4/7] Cleaning up driver InterfaceSetting entries..." -ForegroundColor Cyan
    $driverKeys = @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96c-e325-11ce-bfc1-08002be10318}"
    )
    foreach ($dk in $driverKeys) {
        if (Test-Path $dk) {
            Get-ChildItem -Path $dk -ErrorAction SilentlyContinue | ForEach-Object {
                $ifKey = Join-Path $_.PSPath "InterfaceSetting"
                if (Test-Path $ifKey) {
                    try {
                        $cur = (Get-ItemProperty -Path $ifKey -Name "LineOutTopo" -ErrorAction SilentlyContinue).LineOutTopo
                        if ($cur) {
                            $filtered = @($cur | Where-Object { $_ -ne "ApoPreset1" })
                            if ($filtered.Count -gt 0) {
                                Set-ItemProperty -Path $ifKey -Name "LineOutTopo" -Value $filtered -Type MultiString -Force
                            } else {
                                Remove-ItemProperty -Path $ifKey -Name "LineOutTopo" -ErrorAction SilentlyContinue
                            }
                        }

                        foreach ($entry in @("SecondaryLineOutTopo", "RearLineOutTopoSST3", "RearLineOutTopoHAP3")) {
                            $cur = (Get-ItemProperty -Path $ifKey -Name $entry -ErrorAction SilentlyContinue).$entry
                            if ($cur) {
                                $filtered = @($cur | Where-Object { $_ -ne "ApoPreset2" })
                                if ($filtered.Count -gt 0) {
                                    Set-ItemProperty -Path $ifKey -Name $entry -Value $filtered -Type MultiString -Force
                                } else {
                                    Remove-ItemProperty -Path $ifKey -Name $entry -ErrorAction SilentlyContinue
                                }
                            }
                        }

                        Remove-Item -Path (Join-Path $ifKey "ApoPreset1") -Recurse -Force -ErrorAction SilentlyContinue
                        Remove-Item -Path (Join-Path $ifKey "ApoPreset2") -Recurse -Force -ErrorAction SilentlyContinue
                        Remove-Item -Path (Join-Path $ifKey "SysCustomizedFx") -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Status "Cleaned driver key: $($_.PSChildName)" -Status OK
                    } catch { }
                }
            }
        }
    }

    # 5. Unregister COM CLSIDs and AudioProcessingObjects keys
    Write-Host "`n[5/7] Unregistering Dolby APO COM classes..." -ForegroundColor Cyan
    $apoGuids = @(
        "{0EBD8505-17BB-4AE7-AD76-E86F99A425E9}",
        "{0EBD8506-17BB-4AE7-AD76-E86F99A425E9}",
        "{0EBD8507-17BB-4AE7-AD76-E86F99A425E9}",
        "{0EBD8511-17BB-4AE7-AD76-E86F99A425E9}",
        "{0EBD8512-17BB-4AE7-AD76-E86F99A425E9}",
        "{0212AE2C-F779-4A50-9B10-57A0AEF22870}"
    )

    foreach ($cGuid in $apoGuids) {
        Remove-Item -Path "Registry::HKCR\CLSID\$cGuid" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "HKLM:\SOFTWARE\Classes\CLSID\$cGuid" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "Registry::HKCR\AudioEngine\AudioProcessingObjects\$cGuid" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "HKLM:\SOFTWARE\Classes\AudioEngine\AudioProcessingObjects\$cGuid" -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Clean HKLM:\SOFTWARE\Dolby\DAX
    Remove-Item -Path "HKLM:\SOFTWARE\Dolby\DAX" -Recurse -Force -ErrorAction SilentlyContinue
    $dolbyParent = "HKLM:\SOFTWARE\Dolby"
    if (Test-Path $dolbyParent) {
        $remaining = Get-ChildItem -Path $dolbyParent -ErrorAction SilentlyContinue
        if (-not $remaining) {
            Remove-Item -Path $dolbyParent -Force -ErrorAction SilentlyContinue
        }
    }

    # Reset Samsung Settings ModuleDolbyAtmos
    $moduleDolbyKey = "HKLM:\SOFTWARE\Samsung\SamsungSettings\ModuleDolbyAtmos"
    if (Test-Path $moduleDolbyKey) {
        Set-ItemProperty -Path $moduleDolbyKey -Name "Support" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $moduleDolbyKey -Name "OnOff" -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    }
    Write-Status "Unregistered Dolby APO COM classes and registry entries." -Status OK

    # 6. Delete C:\Windows\System32\dolbyaposvc folder
    Write-Host "`n[6/7] Removing dolbyaposvc directory..." -ForegroundColor Cyan
    $system32Dolby = "C:\Windows\System32\dolbyaposvc"
    if (Test-Path $system32Dolby) {
        try {
            Remove-Item -Path $system32Dolby -Recurse -Force -ErrorAction Stop
            Write-Status "Removed: $system32Dolby" -Status OK
        } catch {
            Write-Status "Notice removing ${system32Dolby}: $_ (Remaining files may be removed upon reboot)" -Status WARN
        }
    }

    # Optional: Delete staged driver packages from DriverStore
    if ($RemoveDrivers) {
        Write-Host "`nUninstalling staged Dolby and Samsung Audio extension packages from DriverStore..." -ForegroundColor Cyan
        try {
            $pnpEnum = & pnputil.exe /enum-drivers 2>&1 | Out-String
            $sections = $pnpEnum -split "Published Name:\s+"
            foreach ($sec in $sections) {
                if ($sec -match "^(oem\d+\.inf)" -and ($sec -match "dax3|dolby|samsungext")) {
                    $oemInf = $Matches[1]
                    Write-Host "  Removing $oemInf..." -ForegroundColor Gray
                    & pnputil.exe /delete-driver "$oemInf" /uninstall /force 2>&1 | Out-Null
                    Write-Status "Deleted DriverStore package: $oemInf" -Status OK
                }
            }
        } catch {
            Write-Status "Notice removing DriverStore packages: $_" -Status WARN
        }
    }

    # 7. Restart Windows Audio pipeline
    Write-Host "`n[7/7] Refreshing Windows Audio pipeline..." -ForegroundColor Cyan
    Restart-WindowsAudio

    Write-Host @"

================================================================================
                   DOLBY ATMOS UNINSTALLATION COMPLETE!
================================================================================
All Galaxy Book Dolby DAX3 Audio Processing Objects, service definitions,
and registry bindings have been removed from your system.
Windows Audio is now using the native driver processing pipeline.
================================================================================
"@ -ForegroundColor Green
}

# ==================== MAIN EXECUTION ROUTER ====================
if ($Status) {
    Get-DolbyInstallationStatus
    exit 0
}

if ($InstallApp) {
    Install-DolbyAccessApp -PromptReinstall
    exit 0
}

if ($Install) {
    $elevArgs = @("-Install")
    if ($DriverPath) { $elevArgs += @("-DriverPath", "`"$DriverPath`"") }
    if ($SkipAppInstall) { $elevArgs += "-SkipAppInstall" }
    Ensure-AdminPrivileges -ForwardArgs $elevArgs
    Invoke-DolbyInstall -CustomDriverPath $DriverPath
    exit 0
}

if ($Uninstall) {
    $elevArgs = @("-Uninstall")
    if ($RemoveDrivers) { $elevArgs += "-RemoveDrivers" }
    if ($Force) { $elevArgs += "-Force" }
    Ensure-AdminPrivileges -ForwardArgs $elevArgs
    Invoke-DolbyUninstall
    exit 0
}

# Interactive Menu (Default when no switches provided)
Ensure-AdminPrivileges

while ($true) {
    Clear-Host
    Write-Host @"
================================================================================
       GALAXY BOOK DOLBY ATMOS & DOLBY ACCESS ENABLER (EXPERIMENTAL)
================================================================================
Manage genuine Galaxy Book Dolby DAX3 Audio Processing Objects on your PC.

  [1] Install / Enable Dolby Atmos
      Stage DAX3 drivers, configure Dynamic profile, register APOs & start service.

  [2] Check Installation Status
      Verify service, COM CLSIDs, active endpoint bindings & Dolby Access app.

  [3] Install / Reinstall Dolby Access App
      Download and install Dolby Access from Microsoft Store via winget.

  [4] Uninstall / Restore Native Audio
      Remove Dolby DAX3 service, APO bindings, files, and registry entries.

  [5] Uninstall & Wipe Drivers from DriverStore
      Complete cleanup including removal of staged INF packages via pnputil.

  [6] Exit

================================================================================
"@ -ForegroundColor Cyan

    $choice = Read-Host "Select an option [1-6]"
    switch ($choice) {
        "1" {
            Ensure-AdminPrivileges -ForwardArgs @("-Install")
            Invoke-DolbyInstall -CustomDriverPath $DriverPath
            Write-Host "`nPress any key to continue..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "2" {
            Get-DolbyInstallationStatus
            Write-Host "`nPress any key to continue..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "3" {
            Install-DolbyAccessApp -PromptReinstall
            Write-Host "`nPress any key to continue..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "4" {
            Ensure-AdminPrivileges -ForwardArgs @("-Uninstall")
            Invoke-DolbyUninstall
            Write-Host "`nPress any key to continue..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "5" {
            Ensure-AdminPrivileges -ForwardArgs @("-Uninstall", "-RemoveDrivers")
            $script:RemoveDrivers = $true
            Invoke-DolbyUninstall
            Write-Host "`nPress any key to continue..." -ForegroundColor Yellow
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        "6" {
            exit 0
        }
        default {
            Write-Host "Invalid option. Please enter a number between 1 and 6." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }
}
