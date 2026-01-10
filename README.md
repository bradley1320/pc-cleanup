# PC Clean

A fancy terminal-based Windows optimization toolkit with a colorful UI.

![PC Clean Screenshot](screenshot.png)

## Features

| Feature | Description |
|---------|-------------|
| **Quick Clean** | Clears temp files, browser caches, recycle bin, Windows Update cache |
| **Startup Manager** | View and disable bloat programs that slow down boot time |
| **Performance Mode** | Sets High Performance power plan, disables transparency/animations, enables Game Mode |
| **Network Reset** | Flushes DNS, resets Winsock and TCP/IP stack |
| **Disk Analysis** | Visual drive usage bars + top 10 largest folders |
| **Full Tune-Up** | Runs everything including DISM component cleanup (10-15 min) |
| **Create Backup** | Saves current settings before optimization |
| **Restore Backup** | Reverts to your saved settings if needed |

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
For full functionality (Prefetch cleanup, DISM, network reset, system restore points), right-click PowerShell → **Run as Administrator**

## What's New in v1.2

- **Backup/Restore Manager** - Save your settings before optimizing, restore anytime
- **System Restore Point** - Option to create Windows restore point before Full Tune-Up
- **Auto-backup** - Full Tune-Up automatically saves your settings first
- **Better UX** - Press Enter to continue (instead of any key)

## Safety

This script:
- Only deletes temporary/cache files that Windows regenerates
- Does not modify system files
- Does not install anything
- Creates backups before making changes
- Is fully open source - review the code yourself

**Use at your own risk.** While designed to be safe, always ensure you have backups of important data.

## License

MIT License - see [LICENSE](LICENSE)

## Roadmap

- [ ] Thermal check before optimization
- [ ] `-WhatIf` dry-run mode
- [ ] Log file output
