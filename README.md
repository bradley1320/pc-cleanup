# PC Cleanup v2

> The Windows optimizer you can read, understand, and undo -- one tweak at a time.

PC Cleanup is an open-source PowerShell toolkit that cleans junk files, optimizes performance settings, disables telemetry and tracking, checks security health, and proves its results with before/after metrics.

Every change is explained in plain English, every change is reversible, and the code is designed to be pasted into AI for verification.

## Quick Start

1. Download the latest release ZIP from [Releases](https://github.com/bradley1320/pc-cleanup/releases)
2. **Right-click the ZIP > Properties > check "Unblock" > OK** (mandatory -- without this, Windows blocks unsigned scripts)
3. Extract the ZIP
4. Right-click `Run.bat` > **Run as Administrator**

That's it. No install, no dependencies, no internet required.

## Requirements

- Windows 10 or Windows 11 (any edition)
- PowerShell 5.1 (built into Windows -- no additional install needed)
- Administrator privileges (recommended for full functionality; most features work without admin)

## What It Does

### Modules

| # | Module | Description | Modifies System? |
|---|--------|-------------|-----------------|
| 1 | **Quick Clean** | Remove temp files, browser caches, recycle bin, Windows Update cache | Yes (deletes files) |
| 2 | **Startup Manager** | View and manage startup programs with publisher info and risk indicators | Yes (registry) |
| 3 | **Performance Mode** | Optimize visual effects, power plan, gaming settings | Yes (registry) |
| 4 | **Privacy Shield** | Disable telemetry, tracking, advertising, Cortana, Copilot | Yes (registry, services, tasks) |
| 5 | **Network Reset** | DNS flush, Winsock reset, TCP/IP reset (standalone troubleshooting) | Yes (network stack) |
| 6 | **Disk Analysis** | View drive usage and folder sizes | No (read-only) |
| 7 | **Security Check** | Check Defender, firewall, SMBv1, update status | No (read-only) |
| 8 | **System Report** | Before/after metrics: boot time, processes, disk space | No (read-only) |
| 9 | **Full Tune-Up** | Run all safe-tier optimizations in one flow | Yes |
| 10 | **Backup & Restore** | View and undo any applied changes | Yes (restores) |

### Tweak Catalog

29 data-driven tweaks defined in `config/tweaks.json`:
- **20 Privacy tweaks** -- telemetry, advertising, activity history, Cortana, Copilot, error reporting, and more
- **9 Performance tweaks** -- visual effects, transparency, game mode, power plan, startup delay, and more

Every tweak is categorized by risk:
- **Safe (18 tweaks)** -- applied by default in Full Tune-Up. No functionality impact.
- **Moderate (8 tweaks)** -- user must explicitly opt in. May affect specific features (e.g., disabling DiagTrack can break Xbox achievements).
- **Advanced (3 tweaks)** -- power users only. Significant breakage potential (e.g., firewall rules blocking telemetry endpoints).

## CLI Usage

```powershell
.\pccleanup.ps1                              # Interactive menu (default)
.\pccleanup.ps1 -Profile Safe                # Apply all safe-tier tweaks
.\pccleanup.ps1 -Profile Gaming              # Gaming-optimized preset
.\pccleanup.ps1 -Profile Privacy             # Maximum privacy preset (moderate tier)
.\pccleanup.ps1 -Module Privacy -Risk moderate  # Specific module + risk level
.\pccleanup.ps1 -WhatIf                      # Dry-run: preview all changes without applying
.\pccleanup.ps1 -Undo All                    # Revert all applied tweaks
.\pccleanup.ps1 -Undo "DisableTelemetry"     # Revert a specific tweak
.\pccleanup.ps1 -Report                      # Show security health report
.\pccleanup.ps1 -Snapshot Before             # Take before snapshot
.\pccleanup.ps1 -Snapshot Compare            # Compare before/after metrics
```

### Profiles

| Profile | Risk Level | What It Does |
|---------|-----------|--------------|
| Safe | safe | Quick Clean + Performance + Privacy (safe tweaks only) |
| Gaming | safe | Quick Clean + Performance (optimized for gaming) |
| Privacy | moderate | Privacy tweaks (includes moderate tier like DiagTrack) |
| Custom | -- | Launches interactive menu with all options |

## Safety Design

PC Cleanup creates multiple safety layers before making any changes:

1. **System Restore Point** -- automatic before the first modification (graceful fallback if System Restore is disabled)
2. **Registry backup** -- timestamped .reg export of modified hives
3. **Per-tweak undo log** -- captures the actual current values on YOUR system at apply time, stored in `%LOCALAPPDATA%\PCCleanup\undo_log.json`
4. **Change logging** -- every operation is logged with timestamps

### Undo System

The undo system captures your actual system state before each change -- not hardcoded defaults. If you already customized a setting, undoing restores YOUR value, not Microsoft's default.

- Undo a specific tweak: menu option 10 > select tweak, or `.\pccleanup.ps1 -Undo "TweakName"`
- Undo everything: menu option 10 > Undo All, or `.\pccleanup.ps1 -Undo All`
- Last resort: use System Restore to the automatic restore point

## Is This Safe?

This tool is designed for transparency. Here's how to verify it yourself:

### Option 1: Read the Code

The compiled `pccleanup.ps1` is a single PowerShell script. Open it in any text editor and read it. Every function is documented with comment-based help.

### Option 2: Read the Tweak Catalog

Open `config/tweaks.json` in any text editor or JSON viewer. Every tweak lists:
- What registry keys it changes and to what values
- What services it modifies
- What scheduled tasks it disables
- A `docsUrl` linking to Microsoft's official documentation
- A `detail` field explaining what the tweak does and what might break

### Option 3: Ask AI to Verify

Copy any module or the entire script into ChatGPT, Claude, Gemini, or any AI and ask:

**For the whole tool:**
> "Review this PowerShell script. Does it do anything malicious? Does it make any irreversible changes? Does it access the network? Does it collect or transmit any data?"

**For specific modules:**
> "Review this PowerShell function. What registry keys does it modify? Are the changes reversible? Could it break anything?"

**For the tweak catalog:**
> "Review this JSON file. For each tweak, verify that the registry paths are legitimate Windows settings and the described behavior matches what the values actually do."

### Option 4: Use -WhatIf

Run `.\pccleanup.ps1 -WhatIf` to see exactly what would happen without making any changes. Every module supports WhatIf mode.

## What This Tool Does NOT Do

These features are deliberately excluded:

- **Registry cleaning** -- Microsoft says don't do it. Malwarebytes calls it snake oil. Registry "errors" don't affect performance.
- **RAM boosting / memory freeing** -- Forces Windows to flush its smart caching (SuperFetch), actively making your PC slower.
- **Driver installation** -- Too risky for an automated tool. We inform, not install.
- **Disabling Windows Update** -- Security risk. Your PC needs updates.
- **Disabling Windows Defender** -- Security risk. Your PC needs antivirus.
- **Disabling UAC** -- Lowers your security posture. Always harmful.
- **Disabling PageFile** -- Myth that it helps with high RAM. Causes out-of-memory crashes under load.
- **Disabling SysMain/SuperFetch** -- Myth that it helps SSDs. It intelligently preloads apps with near-zero I/O. Disabling it makes things slower.
- **Removing UWP/Appx packages** -- Functionally irreversible on Windows 11 24H2. Breaks the Microsoft Store and can break File Explorer.
- **App installation** -- Not our scope. Use [WinUtil](https://github.com/ChrisTitusTech/winutil) for that.
- **GUI** -- A GUI would defeat the "paste into AI to verify" transparency model.

## Troubleshooting

### "Windows protected your PC" (SmartScreen)

You forgot to unblock the ZIP. Right-click the ZIP > Properties > check "Unblock" > OK, then re-extract.

### Script opens and immediately closes

This is likely AMSI (Antimalware Scan Interface) blocking execution. Add the extracted folder to Windows Defender's exclusion list:
1. Open Windows Security > Virus & threat protection > Manage settings
2. Scroll to Exclusions > Add or remove exclusions
3. Add the folder where you extracted PC Cleanup

### "Running scripts is disabled on this system"

The `Run.bat` launcher sets `-ExecutionPolicy Bypass` which should handle this. If you're running `pccleanup.ps1` directly, run this first:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### A tweak didn't seem to work

Some changes (especially visual effects and taskbar tweaks) require Explorer to restart. The tool broadcasts a settings change notification, but if that doesn't work, restart Explorer manually or reboot.

### Boot time didn't improve after Full Tune-Up

The first reboot after changes is often slower. Restart twice before taking an "after" snapshot. Boot time measurement uses Event ID 100 when available, with a WMI fallback (if privacy tweaks disabled diagnostic logging, the fallback is less granular).

## Project Structure

### What You Download (dist/)
```
pc-cleanup-v2.zip
  pccleanup.ps1       # Single compiled script (all source concatenated)
  Run.bat              # Right-click > Run as Administrator
  config/
    tweaks.json        # Tweak catalog (inspect and modify)
    apps-bloat.json    # Known bloatware startup programs
    apps-critical.json # Critical programs (do not disable)
    profiles.json      # Preset profiles
```

Config files ship separately so you can inspect and modify them. The tweak catalog is readable data, not buried code.

### Source (for developers)
```
src/
  core/           # Infrastructure: utility, system info, safety, tweak engine, undo, file ops
  handlers/       # Registry, service, scheduled task, script handlers
  modules/        # Feature modules (Quick Clean, Privacy Shield, etc.)
  ui/             # Interactive menu system
  main.ps1        # Entry point and CLI dispatch
config/           # JSON configuration files
tests/unit/       # 457 Pester tests (mocked, no admin needed)
build/            # Build.ps1 (concatenate source > single .ps1)
```

## Building from Source

```powershell
# Run tests
Import-Module Pester -RequiredVersion 5.6.1
$c = New-PesterConfiguration
$c.Run.Path = "./tests/unit/"
Invoke-Pester -Configuration $c

# Build distribution
.\build\Build.ps1

# Output goes to dist/
```

## Changelog

### v2.0 (2026)

Complete modular rewrite:
- **Modular architecture** -- 20 source files organized by responsibility (core, handlers, modules, UI)
- **Data-driven tweaks** -- 29 tweaks defined in JSON, not hardcoded in functions
- **Per-tweak undo** -- captures actual system state at apply time, not hardcoded defaults
- **Privacy Shield** -- 20 privacy tweaks across 3 risk tiers with Microsoft docs links
- **Performance Mode** -- 9 performance tweaks with laptop/SSD detection
- **CLI support** -- profiles, modules, risk levels, WhatIf, undo, snapshots
- **Security Check** -- read-only health report (Defender, firewall, SMBv1, updates)
- **System Report** -- before/after metrics with boot time measurement
- **Disk Analysis** -- drive usage and folder size analysis
- **Network Reset** -- isolated from optimization flow with explicit warnings
- **457 unit tests** -- Pester 5, mocked, no admin needed
- **0 PSScriptAnalyzer warnings** -- clean linting on every commit
- **CI/CD** -- GitHub Actions: lint, test, build on every push

### v1.2 (2025)

Original monolithic script. Single-file optimizer with basic cleanup, startup management, and privacy tweaks.

## How It's Built

This project is built with [Claude Code](https://claude.ai/claude-code) (Anthropic) and designed in collaboration with Claude. The full specification is in [CLAUDE.md](CLAUDE.md), including council reviews from Grok, Gemini, and DeepSeek.

AI-assisted development is how this project works -- we don't hide it, we own it. The code is open source and fully auditable regardless of how it was written.

## License

[MIT](LICENSE) -- free to use, modify, and distribute.
