# PC Clean

A fancy terminal-based Windows optimization toolkit with a colorful UI.

![PC Clean Banner](https://github.com/John-AI-Labs/pc-cleanup/raw/main/screenshot.png)

## Features

| Feature | Description |
|---------|-------------|
| **Quick Clean** | Clears temp files, browser caches, recycle bin, Windows Update cache |
| **Startup Manager** | View and disable bloat programs that slow down boot time |
| **Performance Mode** | Sets High Performance power plan, disables transparency/animations, enables Game Mode |
| **Network Reset** | Flushes DNS, resets Winsock and TCP/IP stack |
| **Disk Analysis** | Visual drive usage bars + top 10 largest folders |
| **Full Tune-Up** | Runs everything including DISM component cleanup (10-15 min) |

## Quick Start

### Option 1: Double-click (easiest)
1. Download `PCCleanup.ps1` and `Run.bat`
2. Double-click `Run.bat`

### Option 2: PowerShell
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
.\PCCleanup.ps1
```

### Run as Administrator
For full functionality (Prefetch cleanup, DISM, network reset), right-click PowerShell → **Run as Administrator**

## What It Does

### Quick Clean
- Windows temp folders (`%TEMP%`, `C:\Windows\Temp`)
- Browser caches (Chrome, Edge, Firefox) - skips if browser is running
- Recycle Bin
- Windows Update download cache (admin only)

### Startup Manager
- Scans Registry Run keys + Startup folder
- Auto-disable common bloat: Discord, Steam, Spotify, Epic Games, OneDrive, etc.
- Or manually disable individual items

### Performance Mode
- Sets **High Performance** power plan (falls back to Ultimate Performance if unavailable)
- Disables transparency and animations
- Reduces menu delay
- Enables Game Mode, disables Game Bar overlay

### Network Reset
- Flushes DNS cache
- Resets Winsock catalog (admin)
- Resets TCP/IP stack (admin)
- Clears ARP cache (admin)

### Full Tune-Up (Admin)
All of the above, plus:
- Prefetch cleanup
- DISM Component Cleanup (WinSxS) - can recover 2-10GB

## Smart Features

- **Pending Reboot Detection** - Warns if Windows updates are waiting
- **Browser Detection** - Skips cache cleaning for running browsers
- **Power Plan Fallback** - Tries Ultimate Performance if High Performance is unavailable
- **Admin Awareness** - Shows what features are limited without admin rights

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Administrator rights recommended

## Safety

This script:
- Only deletes temporary/cache files that Windows regenerates
- Does not modify system files
- Does not install anything
- Is fully open source - review the code yourself

**Use at your own risk.** While designed to be safe, always ensure you have backups of important data.

## License

MIT License - see [LICENSE](LICENSE)

## Contributing

Issues and PRs welcome. This started as a personal tool and grew from there.

## Roadmap

- [ ] Backup/restore functionality
- [ ] `-WhatIf` dry-run mode
- [ ] Log file output
- [ ] Scheduled task integration
