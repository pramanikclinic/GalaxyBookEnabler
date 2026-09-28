# Galaxy Book Enabler - Donor Profile Exporter
# Captures authentic SMBIOS, Registry, Driver, WMI, and App data from genuine Samsung Galaxy Book hardware
# Copyright (c) 2023-2026 Glen Muthoka Mutinda & Contributors

<#
.SYNOPSIS
    Exports genuine Samsung Galaxy Book hardware profiles, driver metadata, registry
    branches, WMI classes, and ecosystem app definitions for the GalaxyBookEnabler project.

.DESCRIPTION
    This script is designed to run on genuine Samsung Galaxy Book devices (Book2, Book3,
    Book4, Book5, etc.). It collects authentic system telemetry, SMBIOS properties,
    Samsung Settings modules, Samsung System Support Service (SSSE) parameters, and installed
    ecosystem apps.

    The exported donor package includes:
    1. Hardware & SMBIOS JSON (Win32_BIOS, Win32_ComputerSystem, Win32_BaseBoard, Win32_SystemEnclosure)
    2. Model Blueprint draft ready to paste into Install-GalaxyBookEnabler.ps1
    3. Exported Registry branches (HKLM\SOFTWARE\Samsung, Services, HardwareConfig, BIOS)
    4. Samsung drivers metadata (pnputil, INF owners, and optional driver store export)
    5. Samsung ACPI / WMI class enumeration from root\wmi
    6. Installed Samsung AppX / MSIX package manifest and Win32 software
    7. Human-readable Markdown summary report

.PARAMETER OutputPath
    Directory where the exported profile data will be saved.
    Defaults to .\GalaxyBook-DonorProfile-<Timestamp>.

.PARAMETER Sanitize
    Sanitizes personal identifiers (serial numbers, username paths, connected device names).
    Default is $true. Pass -Sanitize:$false to preserve raw serial numbers for private backups.

.PARAMETER IncludeDrivers
    Exports third-party Samsung driver packages directly from DriverStore using Export-WindowsDriver.
    Default is $false (metadata only).

.PARAMETER ExportDolbyDrivers
    Exports genuine Dolby DAX3 and Samsung Audio Extension driver packages from DriverStore
    (FileRepository) into Drivers\DolbyDrivers. Essential for activating Dolby Access on other PCs.
    Default is $false.

.PARAMETER Zip
    Compresses the exported folder into a timestamped ZIP file.
    Default is $false.

.PARAMETER NonInteractive
    Runs without user prompts or confirmation pauses.

.EXAMPLE
    .\Export-GalaxyBookDonorProfile.ps1
    Exports sanitized profile to a new folder with interactive progress.

.EXAMPLE
    .\Export-GalaxyBookDonorProfile.ps1 -ExportDolbyDrivers -Zip
    Exports profile along with genuine Galaxy Book Dolby DAX3 drivers and creates a ZIP archive.

.EXAMPLE
    .\Export-GalaxyBookDonorProfile.ps1 -IncludeDrivers -Zip
    Exports profile, exports Samsung driver files from DriverStore, and creates a ZIP archive.

.EXAMPLE
    .\Export-GalaxyBookDonorProfile.ps1 -Sanitize:$false -OutputPath "C:\SamsungBackup"
    Exports complete raw backup including exact serial numbers.
#>

[CmdletBinding()]
param(
    [string]$OutputPath,
    [bool]$Sanitize = $true,
    [switch]$IncludeDrivers,
    [switch]$ExportDolbyDrivers,
    [switch]$Zip,
    [switch]$NonInteractive,
    [switch]$AllowNonAdmin
)

Set-StrictMode -Off
$ErrorActionPreference = 'Continue'

# ============================================================================
# ELEVATION CHECK
# ============================================================================
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    if ($AllowNonAdmin) {
        Write-Host "[!] Running with standard user privileges (-AllowNonAdmin)." -ForegroundColor Yellow
        Write-Host "    Some system registry keys and DriverStore exports will be limited or skipped." -ForegroundColor Gray
    }
    else {
        Write-Host "[!] Administrator privileges recommended for complete Registry and DriverStore export." -ForegroundColor Yellow
        Write-Host "    Attempting to elevate..." -ForegroundColor Cyan

        $scriptPath = $PSCommandPath
        if (-not $scriptPath) {
            $scriptPath = $MyInvocation.MyCommand.Definition
        }

        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        if ($OutputPath) { $arguments += " -OutputPath `"$OutputPath`"" }
        if (-not $Sanitize) { $arguments += " -Sanitize:`$false" }
        if ($IncludeDrivers) { $arguments += " -IncludeDrivers" }
        if ($ExportDolbyDrivers) { $arguments += " -ExportDolbyDrivers" }
        if ($Zip) { $arguments += " -Zip" }
        if ($NonInteractive) { $arguments += " -NonInteractive" }

        $elevated = $false
        try {
            $elevatedProcess = Start-Process -FilePath "pwsh.exe" -ArgumentList $arguments -Verb RunAs -PassThru -ErrorAction Stop
            exit $elevatedProcess.ExitCode
        }
        catch {
            try {
                $elevatedProcess = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -Verb RunAs -PassThru -ErrorAction Stop
                exit $elevatedProcess.ExitCode
            }
            catch {
                Write-Host "    [-] Could not elevate automatically. Continuing with standard user permissions..." -ForegroundColor Yellow
                Write-Host "        (Tip: Run PowerShell as Administrator for 100% full export)" -ForegroundColor DarkGray
            }
        }
    }
}

# ============================================================================
# INITIALIZATION & DIRECTORY SETUP
# ============================================================================
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

if (-not $OutputPath) {
    $scriptDir = Split-Path -Parent $PSCommandPath
    if (-not $scriptDir) { $scriptDir = $PWD.Path }
    $OutputPath = Join-Path $scriptDir "GalaxyBook-DonorProfile-$timestamp"
}

$RegistryDir = Join-Path $OutputPath "Registry"
$DriversDir  = Join-Path $OutputPath "Drivers"
$WmiDir      = Join-Path $OutputPath "WMI"
$AppsDir     = Join-Path $OutputPath "Apps"

New-Item -Path $OutputPath  -ItemType Directory -Force | Out-Null
New-Item -Path $RegistryDir -ItemType Directory -Force | Out-Null
New-Item -Path $DriversDir  -ItemType Directory -Force | Out-Null
New-Item -Path $WmiDir      -ItemType Directory -Force | Out-Null
New-Item -Path $AppsDir     -ItemType Directory -Force | Out-Null

function Write-DonorHeader {
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "                GALAXY BOOK ENABLER - DONOR PROFILE EXPORTER                   " -ForegroundColor White
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "Output Directory : $OutputPath" -ForegroundColor Gray
    Write-Host "Sanitization     : $(if ($Sanitize) { 'Enabled (serials, paths & personal IDs masked)' } else { 'Disabled (exact raw values)' })" -ForegroundColor Gray
    Write-Host "Export Drivers   : $(if ($IncludeDrivers) { 'Yes (Export-WindowsDriver)' } else { 'Metadata Only' })" -ForegroundColor Gray
    Write-Host "Dolby Drivers    : $(if ($ExportDolbyDrivers) { 'Yes (Galaxy Book DAX3 & Samsung Audio Extensions)' } elseif ($IncludeDrivers) { 'Included with all drivers' } else { 'No' })" -ForegroundColor Gray
    Write-Host "Create ZIP       : $(if ($Zip) { 'Yes' } else { 'No' })" -ForegroundColor Gray
    Write-Host "Timestamp        : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "================================================================================`n" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "[$Step] " -NoNewline -ForegroundColor Yellow
    Write-Host "$Message..." -ForegroundColor White
}

function Write-Success {
    param([string]$Message)
    Write-Host "      [+] $Message" -ForegroundColor Green
}

function Write-WarningLog {
    param([string]$Message)
    Write-Host "      [!] $Message" -ForegroundColor DarkYellow
}

function Mask-String {
    param([string]$InputString, [int]$KeepChars = 4)
    if ([string]::IsNullOrWhiteSpace($InputString)) { return $InputString }
    if (-not $Sanitize) { return $InputString }
    if ($InputString.Length -le $KeepChars) { return "REDACTED" }
    $prefix = $InputString.Substring(0, [Math]::Min($KeepChars, $InputString.Length))
    $masked = "*" * ($InputString.Length - $prefix.Length)
    return "$prefix$masked"
}

Write-DonorHeader

# ============================================================================
# STEP 1: SMBIOS & HARDWARE IDENTIFICATION
# ============================================================================
Write-Step "1/6" "Collecting SMBIOS & Hardware Attributes"

$hwProfile = [ordered]@{}

try {
    $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
    $hwProfile["BIOS"] = [ordered]@{
        Manufacturer           = $bios.Manufacturer
        Name                   = $bios.Name
        SMBIOSBIOSVersion      = $bios.SMBIOSBIOSVersion
        Version                = $bios.Version
        ReleaseDate            = if ($bios.ReleaseDate) { $bios.ReleaseDate.ToString("yyyy-MM-dd") } else { $null }
        SystemBiosMajorVersion = $bios.SystemBiosMajorVersion
        SystemBiosMinorVersion = $bios.SystemBiosMinorVersion
        SMBIOSMajorVersion     = $bios.SMBIOSMajorVersion
        SMBIOSMinorVersion     = $bios.SMBIOSMinorVersion
        SerialNumber           = Mask-String $bios.SerialNumber 4
    }
    Write-Success "Win32_BIOS: $($bios.Manufacturer) - $($bios.SMBIOSBIOSVersion)"
}
catch {
    Write-WarningLog "Failed to query Win32_BIOS: $_"
}

try {
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $hwProfile["ComputerSystem"] = [ordered]@{
        Manufacturer        = $cs.Manufacturer
        Model               = $cs.Model
        SystemFamily        = $cs.SystemFamily
        SystemSKUNumber     = $cs.SystemSKUNumber
        SystemType          = $cs.SystemType
        TotalPhysicalMemory = $cs.TotalPhysicalMemory
        UserName            = if ($Sanitize) { "USER_REDACTED" } else { $cs.UserName }
    }
    Write-Success "Win32_ComputerSystem: $($cs.Manufacturer) $($cs.Model) ($($cs.SystemFamily))"
}
catch {
    Write-WarningLog "Failed to query Win32_ComputerSystem: $_"
}

try {
    $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop
    $hwProfile["BaseBoard"] = [ordered]@{
        Manufacturer = $board.Manufacturer
        Product      = $board.Product
        Version      = $board.Version
        SerialNumber = Mask-String $board.SerialNumber 4
    }
    Write-Success "Win32_BaseBoard: Product '$($board.Product)' (Manufacturer: '$($board.Manufacturer)')"
}
catch {
    Write-WarningLog "Failed to query Win32_BaseBoard: $_"
}

try {
    $enclosure = Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop
    $hwProfile["SystemEnclosure"] = [ordered]@{
        Manufacturer = $enclosure.Manufacturer
        ChassisTypes = $enclosure.ChassisTypes
        ChassisName  = ($enclosure.ChassisTypes | ForEach-Object {
            switch ($_) {
                1  { "Other" }
                2  { "Unknown" }
                8  { "Portable" }
                9  { "Laptop" }
                10 { "Notebook" }
                11 { "Hand Held" }
                30 { "Tablet" }
                31 { "Convertible" }
                32 { "Detachable" }
                default { "Type $_" }
            }
        }) -join ", "
        Version      = $enclosure.Version
        SerialNumber = Mask-String $enclosure.SerialNumber 4
    }
    Write-Success "Win32_SystemEnclosure: ChassisType $($enclosure.ChassisTypes -join ', ') ($($hwProfile.SystemEnclosure.ChassisName))"
}
catch {
    Write-WarningLog "Failed to query Win32_SystemEnclosure: $_"
}

try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    $hwProfile["Processor"] = [ordered]@{
        Name                      = $cpu.Name
        Manufacturer              = $cpu.Manufacturer
        NumberOfCores             = $cpu.NumberOfCores
        NumberOfLogicalProcessors = $cpu.NumberOfLogicalProcessors
    }
    Write-Success "Processor: $($cpu.Name)"
}
catch {
    Write-WarningLog "Failed to query Win32_Processor: $_"
}

try {
    $netAdapters = Get-CimInstance Win32_NetworkAdapter -ErrorAction SilentlyContinue | Where-Object {
        $_.NetConnectionStatus -ne $null -or $_.AdapterType -like "*Ethernet*" -or $_.AdapterType -like "*Wireless*"
    }
    $hwProfile["NetworkAdapters"] = @($netAdapters | ForEach-Object {
        [ordered]@{
            Name         = $_.Name
            AdapterType  = $_.AdapterType
            Manufacturer = $_.Manufacturer
            MACAddress   = if ($Sanitize) { "XX:XX:XX:XX:XX:XX" } else { $_.MACAddress }
            DriverDate   = $_.TimeOfLastReset
        }
    })
    Write-Success "Network Adapters: $($netAdapters.Count) adapters recorded"
}
catch {
    Write-WarningLog "Failed to query network adapters: $_"
}

$hwProfileJsonPath = Join-Path $OutputPath "Hardware-SMBIOS.json"
$hwProfile | ConvertTo-Json -Depth 6 | Set-Content -Path $hwProfileJsonPath -Encoding UTF8

# ============================================================================
# STEP 2: GENERATE MODEL BLUEPRINT DRAFT
# ============================================================================
Write-Step "2/6" "Deriving Galaxy Book Model Blueprint"

$rawModel     = $cs.Model
$rawFamily    = $cs.SystemFamily
$rawBiosVer   = $bios.SMBIOSBIOSVersion
$rawBoardProd = $board.Product
$chassisType  = if ($enclosure.ChassisTypes) { $enclosure.ChassisTypes[0] } else { 10 }

# Normalize model key (remove NP prefix and non-alphanumeric chars)
$cleanModel = ($rawModel -replace '^NP', '') -replace '[^A-Za-z0-9]', ''
$modelKey   = if ($cleanModel.Length -ge 6) { $cleanModel.Substring(0, 6).ToUpperInvariant() } else { $cleanModel.ToUpperInvariant() }

# Detect BiosCode from sample: e.g., P05AMA.058.250810.01 -> AMA
$biosCode = if ($rawBiosVer -match '^P\d{2}([A-Z0-9]{3})\.') { $Matches[1] } else { 'UNK' }

# Derive FamilyKey
$familyKey = switch -Regex ($rawFamily) {
    'Book5.*Pro.*360' { 'Book5Pro360'; break }
    'Book5.*Pro'     { 'Book5Pro'; break }
    'Book5.*360'     { 'Book5360'; break }
    'Book5'          { 'Book5'; break }
    'Book4.*Ultra'   { 'Book4Ultra'; break }
    'Book4.*Pro.*360' { 'Book4Pro360'; break }
    'Book4.*Pro'     { 'Book4Pro'; break }
    'Book4.*360'     { 'Book4360'; break }
    'Book4'          { 'Book4'; break }
    'Book3.*Ultra'   { 'Book3Ultra'; break }
    'Book3.*Pro.*360' { 'Book3Pro360'; break }
    'Book3.*Pro'     { 'Book3Pro'; break }
    'Book3.*360'     { 'Book3360'; break }
    'Book3'          { 'Book3'; break }
    'Book2.*Pro'     { 'Book2Pro'; break }
    'Book2'          { 'Book2'; break }
    default          { ($rawFamily -replace '[^A-Za-z0-9]', '') }
}

# Infer Board Suffix if possible
$boardSuffix = if ($rawBoardProd -match 'NP[A-Za-z0-9]{6}-([A-Za-z0-9]+)') { $Matches[1] } else { 'KG1' }

# Guess Board Region from SKU / Country
$boardRegion = 'US'
if ($cs.SystemSKUNumber -match '-([A-Z]{2})') {
    $boardRegion = $Matches[1]
}

# Major/Minor release
$majorRel = if ($bios.SystemBiosMajorVersion) { $bios.SystemBiosMajorVersion } else { 5 }
$minorRel = if ($bios.SystemBiosMinorVersion) { $bios.SystemBiosMinorVersion } else { 32 }

# Platform and Segment heuristics
$platform = switch -Regex ($cpu.Name) {
    'Core.*Ultra.*Series 2|Lunar Lake' { 'LNLM'; break }
    'Core.*Ultra|Meteor Lake'          { 'MTLH'; break }
    '13th Gen|Raptor Lake'             { 'RPLP'; break }
    '12th Gen|Alder Lake'              { 'ADLP'; break }
    '11th Gen|Tiger Lake'              { 'TGL4'; break }
    default                            { 'A5A5' }
}
$segment = if ($rawFamily -match 'Pro|Ultra') { 'PROT' } else { 'A5A5' }

$blueprintDraft = @"
# ==============================================================================
# Auto-generated Model Blueprint for GalaxyBookEnabler
# Source Model : $rawModel ($rawFamily)
# Generated    : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# ==============================================================================

# Add to `$GalaxyBookModelBlueprints ordered hashtable:
'$modelKey' = @{
    FamilyKey           = '$familyKey'
    BIOSVersionSample   = '$rawBiosVer'
    BIOSMajorRelease    = $majorRel
    BIOSMinorRelease    = $minorRel
    Segment             = '$segment'
    Config              = 'A5A5'
    Platform            = '$platform'
    BiosCode            = '$biosCode'
    BoardSuffix         = '$boardSuffix'
    BoardRegion         = '$boardRegion'
    SupportsRegionBoard = `$true
    EnclosureKind       = $chassisType
}

# Model details:
# Model Key      : $modelKey
# Family Key     : $familyKey
# Product Name   : $($cs.Model)
# BaseBoard      : $($board.Product)
# Chassis Type   : $chassisType ($(if ($chassisType -eq 31) { 'Convertible 360' } else { 'Clamshell Notebook' }))
# BIOS Sample    : $rawBiosVer
"@

$blueprintDraftPath = Join-Path $OutputPath "ModelBlueprint-Draft.ps1"
$blueprintDraft | Set-Content -Path $blueprintDraftPath -Encoding UTF8
Write-Success "Generated draft blueprint for model key '$modelKey' (Family: $familyKey)"

# ============================================================================
# STEP 3: EXPORT RELEVANT REGISTRY BRANCHES
# ============================================================================
Write-Step "3/6" "Exporting Samsung & System Registry Trees"

$registryTargets = @(
    @{ Path = "HKLM\SOFTWARE\Samsung"; File = "Samsung-HKLM.reg"; Label = "Samsung Software Settings" },
    @{ Path = "HKCU\SOFTWARE\Samsung"; File = "Samsung-HKCU.reg"; Label = "Samsung User Preferences" },
    @{ Path = "HKLM\SYSTEM\CurrentControlSet\Services\SamsungSystemSupportService"; File = "SamsungSystemSupportService.reg"; Label = "SSSE Service Config" },
    @{ Path = "HKLM\SYSTEM\CurrentControlSet\Services\SamsungSystemSupportEngine"; File = "SamsungSystemSupportEngine.reg"; Label = "SSSE Engine Service Config" },
    @{ Path = "HKLM\HARDWARE\DESCRIPTION\System\BIOS"; File = "System-BIOS.reg"; Label = "Hardware BIOS Description" },
    @{ Path = "HKLM\SYSTEM\HardwareConfig\Current"; File = "HardwareConfig-Current.reg"; Label = "HardwareConfig Current" },
    @{ Path = "HKLM\SYSTEM\CurrentControlSet\Control\SystemInformation"; File = "SystemInformation.reg"; Label = "SystemInformation Control" }
)

foreach ($target in $registryTargets) {
    $destFile = Join-Path $RegistryDir $target.File
    $regPath  = $target.Path

    if (Test-Path "Registry::$regPath") {
        $exportResult = & reg.exe export $regPath $destFile /y 2>&1
        if ($LASTEXITCODE -eq 0 -and (Test-Path $destFile)) {
            Write-Success "Exported: $($target.Label) -> $($target.File)"

            if ($Sanitize) {
                # Clean personal paths or tokens if present
                try {
                    $lines = Get-Content -Path $destFile
                    $sanitizedLines = $lines | ForEach-Object {
                        $_ -replace '(?i)C:\\Users\\[a-zA-Z0-9_\-\.]+', 'C:\\Users\\USER_REDACTED' `
                           -replace '(?i)"ConnectedDevices"="\[\\".*?\\"\]"', '"ConnectedDevices"="[\"DEVICE_REDACTED\"]"'
                    }
                    $sanitizedLines | Set-Content -Path $destFile -Encoding Unicode
                }
                catch {
                    # Ignore encoding rewrite glitches
                }
            }
        }
        else {
            Write-WarningLog "Could not export ${regPath}: $exportResult"
        }
    }
    else {
        Write-WarningLog "Registry key not present: $regPath"
    }
}

# ============================================================================
# STEP 4: SAMSUNG DRIVERS & DRIVERSTORE
# ============================================================================
Write-Step "4/6" "Enumerating Samsung Drivers & Hardware Components"

try {
    # Query PnP Signed Drivers
    $samsungDrivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue | Where-Object {
        $_.Manufacturer -like "*Samsung*" -or $_.DeviceName -like "*Samsung*" -or $_.HardWareID -like "*SAM042*"
    } | Select-Object DeviceName, Manufacturer, DriverVersion, DriverDate, HardWareID, InfName, IsSigned, CompatID

    $driversJsonPath = Join-Path $DriversDir "Samsung-SignedDrivers.json"
    $samsungDrivers | ConvertTo-Json -Depth 4 | Set-Content -Path $driversJsonPath -Encoding UTF8
    Write-Success "Found $(@($samsungDrivers).Count) Samsung PnP signed drivers"

    # Enumerate PnP Entities (ACPI\SAM*, SWC\SAM*)
    $pnpEntities = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
        $_.DeviceID -like "*SAM042*" -or $_.Manufacturer -like "*Samsung*" -or $_.DeviceID -like "*SAMSUNG*"
    } | Select-Object Name, DeviceID, Manufacturer, Status, Present, Service

    $pnpJsonPath = Join-Path $DriversDir "Samsung-PnPEntities.json"
    $pnpEntities | ConvertTo-Json -Depth 4 | Set-Content -Path $pnpJsonPath -Encoding UTF8
    Write-Success "Found $(@($pnpEntities).Count) Samsung PnP hardware/software devices"

    # Pnputil raw enumeration
    $pnputilOutput = & pnputil.exe /enum-drivers 2>&1
    $pnputilFile   = Join-Path $DriversDir "pnputil-drivers-dump.txt"
    $pnputilOutput | Set-Content -Path $pnputilFile -Encoding UTF8
    Write-Success "Saved full pnputil driver table"

    # Optional: Export complete drivers from DriverStore
    if ($IncludeDrivers) {
        $exportedDriversDir = Join-Path $DriversDir "ExportedDriverStore"
        New-Item -Path $exportedDriversDir -ItemType Directory -Force | Out-Null
        Write-Host "      Exporting online OEM drivers from DriverStore using pnputil..." -ForegroundColor Cyan
        try {
            $pnpOut = & pnputil.exe /export-driver * "$exportedDriversDir" 2>&1
            $exportedInfs = Get-ChildItem -Path $exportedDriversDir -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
            if ($exportedInfs -and $exportedInfs.Count -gt 0) {
                Write-Success "Exported $(@($exportedInfs).Count) driver packages to $exportedDriversDir"
            }
            else {
                # Fallback to DISM
                Write-Host "      pnputil produced no packages, attempting fallback via dism.exe..." -ForegroundColor Cyan
                $dismOut = & dism.exe /Online /Export-Driver /Destination:"$exportedDriversDir" 2>&1
                $exportedInfs = Get-ChildItem -Path $exportedDriversDir -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
                if ($exportedInfs -and $exportedInfs.Count -gt 0) {
                    Write-Success "Exported $(@($exportedInfs).Count) driver packages to $exportedDriversDir via DISM"
                }
                else {
                    # Third fallback to Export-WindowsDriver cmdlet
                    Export-WindowsDriver -Online -Destination $exportedDriversDir -ErrorAction SilentlyContinue | Out-Null
                    $exportedInfs = Get-ChildItem -Path $exportedDriversDir -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
                    if ($exportedInfs -and $exportedInfs.Count -gt 0) {
                        Write-Success "Exported $(@($exportedInfs).Count) driver packages to $exportedDriversDir"
                    }
                    else {
                        Write-WarningLog "Could not export driver packages: $($pnpOut -join ' ')"
                    }
                }
            }
        }
        catch {
            Write-WarningLog "Driver export error: $_"
        }
    }

    # Export Dolby DAX3 & Samsung Audio Extension driver packages
    if ($ExportDolbyDrivers -or $IncludeDrivers) {
        $dolbyDest = Join-Path $DriversDir "DolbyDrivers"
        New-Item -Path $dolbyDest -ItemType Directory -Force | Out-Null
        Write-Host "      Exporting genuine Dolby DAX3 & Samsung Audio Extension drivers..." -ForegroundColor Cyan
        $repoPath = "C:\Windows\System32\DriverStore\FileRepository"
        $dolbyCount = 0
        if (Test-Path $repoPath) {
            Get-ChildItem -Path $repoPath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'dax3|dolby|samsungext' } |
                ForEach-Object {
                    $destPkg = Join-Path $dolbyDest $_.Name
                    try {
                        Copy-Item -Path $_.FullName -Destination $destPkg -Recurse -Force -ErrorAction Stop
                        $dolbyCount++
                        Write-Host "        + Copied $($_.Name)" -ForegroundColor DarkCyan
                    }
                    catch {
                        Write-WarningLog "Failed to copy $($_.Name): $_"
                    }
                }
        }
        if ($dolbyCount -gt 0) {
            Write-Success "Exported $dolbyCount Dolby/Samsung audio driver package(s) to $dolbyDest"
        }
        else {
            Write-WarningLog "No Dolby DAX3 or Samsung audio extension packages found in DriverStore FileRepository."
        }
    }
}
catch {
    Write-WarningLog "Error during driver enumeration: $_"
}

# ============================================================================
# STEP 5: WMI / ACPI CLASSES & SCHEMAS
# ============================================================================
Write-Step "5/6" "Enumerating WMI Classes & ACPI Control Methods"

try {
    # Scan root\wmi for Samsung or hardware control classes
    $wmiClasses = Get-CimClass -Namespace root\wmi -ErrorAction SilentlyContinue | Where-Object {
        $_.CimClassName -match 'Samsung|Acpi|Battery|Thermal|Color'
    } | Select-Object CimClassName, CimSuperClassName

    $wmiClassesFile = Join-Path $WmiDir "Samsung-WmiClasses.json"
    $wmiClasses | ConvertTo-Json -Depth 3 | Set-Content -Path $wmiClassesFile -Encoding UTF8
    Write-Success "Discovered $(@($wmiClasses).Count) potential hardware WMI classes in root\wmi"

    # Attempt to query instances of any Samsung classes
    $samsungWmiData = [ordered]@{}
    foreach ($wClass in ($wmiClasses | Where-Object { $_.CimClassName -like "*Samsung*" })) {
        try {
            $instances = Get-CimInstance -Namespace root\wmi -ClassName $wClass.CimClassName -ErrorAction Stop
            $samsungWmiData[$wClass.CimClassName] = $instances
            Write-Success "Queried instance for WMI class: $($wClass.CimClassName)"
        }
        catch {
            # Some WMI classes require specific parameters or are write-only
        }
    }

    $wmiInstancesFile = Join-Path $WmiDir "Samsung-WmiInstances.json"
    $samsungWmiData | ConvertTo-Json -Depth 4 | Set-Content -Path $wmiInstancesFile -Encoding UTF8
}
catch {
    Write-WarningLog "WMI enumeration error: $_"
}

# ============================================================================
# STEP 6: INSTALLED SAMSUNG APPS & ECOSYSTEM PACKAGES
# ============================================================================
Write-Step "6/6" "Collecting Samsung Ecosystem AppX / MSIX Packages"

try {
    $appxPackages = try {
        Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object {
            $_.Name -like "*Samsung*" -or $_.Publisher -like "*Samsung*"
        } | Select-Object Name, Version, Architecture, Publisher, PackageFullName, PackageFamilyName, InstallLocation
    }
    catch {
        Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -like "*Samsung*" -or $_.Publisher -like "*Samsung*"
        } | Select-Object Name, Version, Architecture, Publisher, PackageFullName, PackageFamilyName, InstallLocation
    }

    $appxJsonPath = Join-Path $AppsDir "Samsung-AppxPackages.json"
    $appxPackages | ConvertTo-Json -Depth 4 | Set-Content -Path $appxJsonPath -Encoding UTF8
    Write-Success "Recorded $(@($appxPackages).Count) Samsung AppX/MSIX packages"

    # Scheduled Tasks
    $samsungTasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
        $_.TaskPath -like "*Samsung*" -or $_.TaskName -like "*Samsung*" -or $_.TaskName -like "*Galaxy*"
    } | Select-Object TaskName, TaskPath, State, @{Name="Action"; Expression={$_.Actions.Execute}}, @{Name="Arguments"; Expression={$_.Actions.Arguments}}

    $tasksJsonPath = Join-Path $AppsDir "Samsung-ScheduledTasks.json"
    $samsungTasks | ConvertTo-Json -Depth 4 | Set-Content -Path $tasksJsonPath -Encoding UTF8
    Write-Success "Recorded $(@($samsungTasks).Count) Samsung scheduled tasks"

    # Running Services
    $samsungServices = Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like "*Samsung*" -or $_.DisplayName -like "*Samsung*"
    } | Select-Object Name, DisplayName, Status, StartType

    $servicesJsonPath = Join-Path $AppsDir "Samsung-Services.json"
    $samsungServices | ConvertTo-Json -Depth 4 | Set-Content -Path $servicesJsonPath -Encoding UTF8
    Write-Success "Recorded $(@($samsungServices).Count) Samsung Windows services"
}
catch {
    Write-WarningLog "App enumeration error: $_"
}

# ============================================================================
# GENERATE SUMMARY REPORT
# ============================================================================
$reportPath = Join-Path $OutputPath "DonorSummary.md"

$engineVersion = "Not Found"
$appVersion = "Not Found"
$samsungSettingsReg = Join-Path $RegistryDir "Samsung-HKLM.reg"
if (Test-Path $samsungSettingsReg) {
    $regText = Get-Content $samsungSettingsReg -Raw -ErrorAction SilentlyContinue
    if ($regText -match '"EngineVersion"="([^"]+)"') { $engineVersion = $Matches[1] }
    if ($regText -match '"AppVersion"="([^"]+)"') { $appVersion = $Matches[1] }
}

$bt3 = [string][char]96 * 3
$summaryContent = @"
# Galaxy Book Donor Profile Summary Report

- **Captured On**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
- **System Model**: $($cs.Manufacturer) $($cs.Model)
- **Family**: $($cs.SystemFamily)
- **System SKU**: $($cs.SystemSKUNumber)
- **BaseBoard**: $($board.Manufacturer) $($board.Product)
- **Chassis Type**: $chassisType ($($hwProfile.SystemEnclosure.ChassisName))
- **SMBIOS BIOS Version**: $($bios.SMBIOSBIOSVersion) (Release: $($bios.ReleaseDate))
- **Detected BiosCode**: $biosCode
- **Derived Model Key**: $modelKey
- **Derived Family Key**: $familyKey
- **Samsung Settings Engine**: $engineVersion (App: $appVersion)
- **Installed Samsung Packages**: $(@($appxPackages).Count) packages detected
- **Dolby Drivers Exported**: $(if (Test-Path (Join-Path $DriversDir "DolbyDrivers")) { 'Yes (Galaxy Book DAX3 & Samsung Extensions)' } else { 'No' })
- **Export Sanitized**: $(if ($Sanitize) { 'Yes (serials and accounts masked)' } else { 'No (raw values preserved)' })

## Quick Share / Ecosystem Drivers
- **Processor**: $($cpu.Name)
- **Platform Guess**: $platform

## Draft Blueprint Entry
$bt3`powershell
'$modelKey' = @{
    FamilyKey           = '$familyKey'
    BIOSVersionSample   = '$rawBiosVer'
    BIOSMajorRelease    = $majorRel
    BIOSMinorRelease    = $minorRel
    Segment             = '$segment'
    Config              = 'A5A5'
    Platform            = '$platform'
    BiosCode            = '$biosCode'
    BoardSuffix         = '$boardSuffix'
    BoardRegion         = '$boardRegion'
    SupportsRegionBoard = `$true
    EnclosureKind       = $chassisType
}
$bt3

## Directory Structure
- ``Hardware-SMBIOS.json``: Comprehensive SMBIOS and CIM hardware attributes.
- ``ModelBlueprint-Draft.ps1``: Model definition formatted for ``Install-GalaxyBookEnabler.ps1``.
- ``Registry/``: Clean .reg exports for Samsung software and service definitions.
- ``Drivers/``: PnP devices, signed driver list, raw pnputil table, and optional Dolby DAX3 drivers.
- ``WMI/``: WMI hardware namespaces and class definitions.
- ``Apps/``: Samsung AppX ecosystem packages, scheduled tasks, and services.
"@

$summaryContent | Set-Content -Path $reportPath -Encoding UTF8

# ============================================================================
# COMPRESS TO ZIP IF REQUESTED
# ============================================================================
$finalZipPath = $null
if ($Zip) {
    Write-Host "`nCompressing output to ZIP archive..." -ForegroundColor Cyan
    $finalZipPath = "$OutputPath.zip"
    try {
        if (Test-Path $finalZipPath) { Remove-Item $finalZipPath -Force }
        Compress-Archive -Path "$OutputPath\*" -DestinationPath $finalZipPath -CompressionLevel Optimal -Force
        Write-Success "ZIP Archive created: $finalZipPath"
    }
    catch {
        Write-WarningLog "ZIP creation failed: $_"
    }
}

# ============================================================================
# FINAL OUTPUT DISPLAY
# ============================================================================
Write-Host "`n================================================================================" -ForegroundColor Green
Write-Host "                DONOR PROFILE EXPORT COMPLETED SUCCESSFULLY!                    " -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Green
Write-Host "  Profile Directory : $OutputPath" -ForegroundColor White
if ($finalZipPath) {
    Write-Host "  ZIP Package       : $finalZipPath" -ForegroundColor Cyan
}
Write-Host "  Summary Report    : $reportPath" -ForegroundColor White
Write-Host "  Draft Blueprint   : $blueprintDraftPath" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Green

Write-Host @"

Next Steps:
1. Open '$reportPath' to inspect the collected donor data.
2. Review the draft blueprint in '$blueprintDraftPath'.
3. Submit or merge the new model blueprint into 'Install-GalaxyBookEnabler.ps1'.
4. Share the sanitized ZIP on GitHub to expand hardware support!

"@ -ForegroundColor Gray

if (-not $NonInteractive) {
    Write-Host "Press Enter to exit..." -ForegroundColor Gray
    Read-Host
}
