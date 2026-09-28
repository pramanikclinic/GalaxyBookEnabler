# Galaxy Book Dolby Atmos & Dolby Access Enabler (Experimental)

> Enable genuine Samsung Galaxy Book Dolby Atmos DAX3 audio processing and Dolby Access on non-Galaxy Book Windows PCs.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207.0%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Windows 11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4.svg?logo=windows11)](https://www.microsoft.com/windows)
[![Dolby DAX3](https://img.shields.io/badge/Dolby-DAX3%20APO-black.svg)](https://www.dolby.com)
[![Status](https://img.shields.io/badge/Status-Experimental-orange.svg)]()

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [Interactive Mode](#interactive-mode)
  - [Command-Line Mode](#command-line-mode)
- [Exporting Drivers from a Donor Galaxy Book](#exporting-drivers-from-a-donor-galaxy-book)
- [Status & Diagnostics](#status--diagnostics)
- [Uninstallation & Rollback](#uninstallation--rollback)
- [Frequently Asked Questions (FAQ)](#frequently-asked-questions-faq)
- [Troubleshooting](#troubleshooting)

---

## Overview

Samsung Galaxy Books feature built-in **Dolby Atmos** sound enhancement powered by **Dolby DAX3 Audio Processing Objects (APO)** and Samsung Audio Extensions. Under normal circumstances, the **Dolby Access** Microsoft Store application checks for genuine OEM driver signatures and refuses to activate speaker enhancement on non-Galaxy Book hardware.

**DolbyAtmosEnabler** is a standalone, experimental utility that:
1. Stages authentic Samsung Galaxy Book Dolby DAX3 drivers and Samsung Audio Extension INF packages into the Windows DriverStore.
2. Registers 32-bit and 64-bit Dolby APO COM classes.
3. Automatically binds Dolby Audio Processing Objects (SFX, MFX, EFX) to your PC's active audio render endpoints (speakers, headphones, HDMI/DisplayPort audio).
4. Patches operator tuning configuration (`operator_settings.xml` and `operator_settings.json`) to unlock the **Dynamic** smart profile and direct Digital Audio Processing (DAP).
5. Configures the `DolbyDAXAPI` system service and Samsung Settings `ModuleDolbyAtmos` integration.

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                      Dolby Access App                       │
│      (Dynamic, Movie, Music, Game, Voice, Custom EQ)        │
└──────────────────────────────┬──────────────────────────────┘
                               │ IPC
┌──────────────────────────────▼──────────────────────────────┐
│                    DolbyDAXAPI Service                      │
│            (C:\Windows\System32\dolbyaposvc)                │
└──────────────────────────────┬──────────────────────────────┘
                               │ APO Pipeline
┌──────────────────────────────▼──────────────────────────────┐
│                  Windows Audio Engine (MMDevices)           │
│     FxProperties Stream Effects (SFX / MFX / EFX)           │
│           dax3_apoksl.dll / dax3_ext_rtk.inf                │
└──────────────────────────────┬──────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────┐
│          Physical Audio Hardware (Realtek / USB / BT)        │
└─────────────────────────────────────────────────────────────┘
```

* **Direct DAP vs Spatial Sound**: Unlike generic Windows Spatial Sound (which often requires "Dolby Atmos for Home Theater" over HDMI), Galaxy Book Dolby DAX3 functions as an **Audio Processing Object (APO)** directly in the audio render pipeline. This means Dolby Atmos virtualization and EQ work on all stereo and multichannel outputs without requiring HDMI Bitstream or Windows Spatial Sound toggles.
* **Smart Tuning Patching**: By configuring `ShowAutoProfileButton=true` and `AutoProfileEnabled=true`, Dolby Access reveals the **Dynamic** profile card, which automatically identifies content (music, movies, games, voice) and dynamically adapts equalization.

---

## Features

- **Genuine OEM Activation**: Activates Dolby Access for built-in/desktop speakers without paying for an individual Microsoft Store license.
- **Dynamic Profile Card**: Enables the intelligent Dynamic content recognition mode in Dolby Access.
- **Full Graphic Equalizer**: Unlocks 10-band graphic equalizer with preset modes (Movie, Music, Game, Voice, and Custom).
- **Universal Endpoint Support**: Automatically discovers and binds to all active audio render endpoints.
- **Safe Elevation**: Supports elevation via `gsudo`, Windows 11 `sudo`, or native UAC.
- **Status & Diagnostics**: Real-time inspection of service health, COM registrations, endpoint bindings, and app status.
- **Non-Destructive Simulation**: Test any operation using `-TestMode` without modifying the system.
- **Clean Uninstaller**: Complete removal of APO bindings, services, files, registry entries, and DriverStore packages.

---

## Prerequisites

1. **Operating System**: Windows 10 (1903+) or Windows 11 (x64 / AMD64).
2. **Audio Hardware**: Any standard High Definition Audio, Realtek ALC, USB DAC, or Bluetooth audio device.
3. **Dolby Access Application**: Available from the [Microsoft Store](https://apps.microsoft.com/detail/9N0866FS04W8) (`9N0866FS04W8`).
4. **Donor Driver Package**: Exported Galaxy Book Dolby drivers placed in one of the following locations:
   - `Drivers\DolbyDrivers`
   - `GalaxyBook-DonorProfile\Drivers\DolbyDrivers`
   - Or supplied via `-DriverPath "<path>"`

---

## Quick Start

### Interactive Mode

Open PowerShell as Administrator (or let the script self-elevate) and run:

```powershell
.\DolbyAtmosEnabler.ps1
```

You will be presented with a menu:

```text
================================================================================
       GALAXY BOOK DOLBY ATMOS & DOLBY ACCESS ENABLER (EXPERIMENTAL)
================================================================================
Manage genuine Galaxy Book Dolby DAX3 Audio Processing Objects on your PC.

  [1] Install / Enable Dolby Atmos
      Stage DAX3 drivers, configure Dynamic profile, register APOs & start service.

  [2] Check Installation Status
      Verify service, COM CLSIDs, active endpoint bindings & Dolby Access app.

  [3] Uninstall / Restore Native Audio
      Remove Dolby DAX3 service, APO bindings, files, and registry entries.

  [4] Uninstall & Wipe Drivers from DriverStore
      Complete cleanup including removal of staged INF packages via pnputil.

  [5] Exit
================================================================================
```

### Command-Line Mode

#### Install / Enable Dolby Atmos
```powershell
.\DolbyAtmosEnabler.ps1 -Install
```

#### Install from Custom Driver Directory
```powershell
.\DolbyAtmosEnabler.ps1 -Install -DriverPath "D:\Backups\GalaxyBook-DolbyDrivers"
```

#### Check Current Status
```powershell
.\DolbyAtmosEnabler.ps1 -Status
```

#### Test / Dry-Run (No System Changes)
```powershell
.\DolbyAtmosEnabler.ps1 -Install -TestMode
.\DolbyAtmosEnabler.ps1 -Uninstall -TestMode
```

#### Uninstall / Restore Default Audio
```powershell
.\DolbyAtmosEnabler.ps1 -Uninstall
```

#### Full Uninstall & DriverStore Package Removal
```powershell
.\DolbyAtmosEnabler.ps1 -Uninstall -RemoveDrivers -Force
```

---

## Exporting Drivers from a Donor Galaxy Book

If you own or have access to a genuine Samsung Galaxy Book:

1. Open PowerShell on the Galaxy Book.
2. Run the donor profile export script with the `-ExportDolbyDrivers` flag:
   ```powershell
   .\Export-GalaxyBookDonorProfile.ps1 -ExportDolbyDrivers
   ```
3. The script exports all Dolby and Samsung audio driver packages to:
   ```text
   GalaxyBook-DonorProfile\Drivers\DolbyDrivers\
   ```
   Including:
   - `dax3_swc_aposvc.inf` (Dolby DAX3 API Service)
   - `dax3_swc_hsa.inf` (Dolby Access Hardware Support Application)
   - `dax3_ext_rtk.inf` (Dolby DAX3 Realtek Audio Extension & Tuning)
   - `hdx_samsungext_dolby_wrap36_rtkgen4.inf` (Samsung Audio Extension Wrapper)
4. Copy the `Drivers\DolbyDrivers` folder to your target machine's `GalaxyBookEnabler` folder.

---

## Status & Diagnostics

Run `.\DolbyAtmosEnabler.ps1 -Status` at any time to verify system health:

```text
================================================================================
                    DOLBY ATMOS STATUS & DIAGNOSTICS
================================================================================
  Service Status:    DolbyDAXAPI [Running] (Startup: Automatic)
  Service Binary:    Present (3.30509.591.0)
  APO COM CLSIDs:    Registered (DAX3 SFX/MFX/EFX)
  DAX Registry:      Configured (Active Profile: Dynamic, Version: 3.30509.591.0)
  Active Endpoints:  2 audio render endpoint(s) bound to Dolby APO
  Dolby Access App:  Installed (Version: 3.27.12250.0)
  Samsung Settings:  ModuleDolbyAtmos Support=1, OnOff=1
================================================================================
```

---

## Uninstallation & Rollback

To safely restore your system to default audio processing:

1. Run:
   ```powershell
   .\DolbyAtmosEnabler.ps1 -Uninstall
   ```
2. The uninstaller will:
   - Stop Dolby Access and DAX background processes.
   - Stop and delete the `DolbyDAXAPI` Windows service.
   - Remove Dolby APO CLSIDs from `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\*\FxProperties`.
   - Remove `InterfaceSetting` presets from `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e96c-e325-11ce-bfc1-08002be10318}`.
   - Unregister COM CLSIDs from `HKCR\CLSID` and `HKLM:\SOFTWARE\Classes`.
   - Clean up `C:\Windows\System32\dolbyaposvc`.
   - Restart the Windows Audio service (`Audiosrv`).

Adding `-RemoveDrivers` will also delete staged OEM INF packages from the Windows DriverStore via `pnputil.exe`.

---

## Frequently Asked Questions (FAQ)

### 1. Does this require a paid Dolby Atmos for Headphones license?
**No.** OEM Dolby Atmos activation (like on Galaxy Books, Lenovo, or Dell laptops) licenses **built-in speakers and connected audio endpoints** via OEM APO drivers. Dolby Atmos for Headphones is an optional personal virtualizer sold separately by Dolby on the Microsoft Store.

### 2. Why don't I see "Dolby Atmos for Home Theater" under Spatial Sound?
"Dolby Atmos for Home Theater" is a Windows Spatial Sound format strictly intended for HDMI bitstreaming to an external AV receiver. Galaxy Book Dolby Atmos uses **direct stream effects (DAP)** in the Windows Audio pipeline, processing sound directly on your speakers/headphones without needing Windows Spatial Sound enabled.

### 3. What is the Dynamic profile?
The **Dynamic** profile uses intelligent scene analysis to automatically detect if you are playing music, watching a movie, playing a game, or listening to dialogue, adjusting the equalizer and surround virtualization in real-time.

---

## Troubleshooting

| Issue | Resolution |
| :--- | :--- |
| **Dolby Access says "Ready to use" but settings cannot be toggled** | Ensure `DolbyDAXAPI` service is running: `Get-Service DolbyDAXAPI`. Run `.\DolbyAtmosEnabler.ps1 -Status` to verify endpoint bindings. |
| **Dynamic Profile option missing** | Ensure `operator_settings.xml` was patched. Re-run `.\DolbyAtmosEnabler.ps1 -Install` to reapply `ShowAutoProfileButton=true`. |
| **No sound after installation** | Restart the Windows Audio service: `Restart-Service Audiosrv -Force`, or reboot your PC. |
| **Dolby drivers folder not found** | Verify that `Drivers\DolbyDrivers` contains `.inf` and `.cat` files, or specify the exact path using `-DriverPath "C:\path"`. |
| **Elevation fails** | Right-click PowerShell, select **Run as Administrator**, and run `.\DolbyAtmosEnabler.ps1`. |

---

## Disclaimer

This project is an independent community tool for research, backup, and interoperability purposes. Dolby, Dolby Atmos, and Dolby Access are registered trademarks of Dolby Laboratories Licensing Corporation. Samsung and Galaxy Book are trademarks of Samsung Electronics Co., Ltd.
