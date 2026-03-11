# PC Cleanup v2

> A Windows optimizer that doesn't hide what it's doing.

Most Windows "optimization" tools are black boxes. You run them, stuff happens, and you hope for the best. PC Cleanup is the opposite -- you can read every tweak it makes, undo any of them, and if you're still not sure, paste the whole thing into an AI and ask it what's going on.

It cleans junk files, tunes performance settings, reins in Windows telemetry, checks your security posture, and gives you before/after metrics so you can see if it actually did anything.

## Quick Start

1. Download the latest release ZIP from [Releases](https://github.com/bradley1320/pc-cleanup/releases)
2. **Right-click the ZIP > Properties > check "Unblock" > OK** (this is mandatory -- Windows blocks unsigned scripts without it)
3. Extract the ZIP
4. Right-click `Run.bat` > **Run as Administrator**

That's it. No installer, no dependencies, no internet connection needed.

## Requirements

- Windows 10 or Windows 11 (any edition)
- PowerShell 5.1 (already on your machine -- it ships with Windows)
- Administrator privileges for full functionality (most features still work without admin)

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

All 29 tweaks live in `config/tweaks.json` -- a plain JSON file you can open in any text editor. No tweaks are buried in code.

- **20 Privacy tweaks** -- telemetry, advertising, activity history, Cortana, Copilot, error reporting, and more
- **9 Performance tweaks** -- visual effects, transparency, game mode, power plan, startup delay, and more

Every tweak has a risk tier:

- **Safe (18 tweaks)** -- these are the defaults in Full Tune-Up. They won't break anything.
- **Moderate (8 tweaks)** -- you have to opt in. Some have real trade-offs (disabling DiagTrack can break Xbox achievements, for instance).
- **Advanced (3 tweaks)** -- for people who know what they're doing. Firewall rules blocking telemetry endpoints, that kind of thing.

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

Before the tool changes anything, it creates a System Restore Point (or skips gracefully if that's disabled on your machine), exports a timestamped `.reg` backup of the registry hives it's about to touch, and saves the actual current value of every setting to an undo log at `%LOCALAPPDATA%\PCCleanup\undo_log.json`. Everything gets a timestamped log entry too. On top of that, the compiled script has SHA-256 hashes of all config files baked in at build time -- if someone tampers with the JSON, you'll get a warning before anything runs.

### Undo System

When you undo a tweak, it doesn't just slam in some generic default. It saved what your machine actually had before the change, so that's what it puts back. If you'd already customized something, you get your setting back, not Microsoft's.

- Undo one tweak: menu option 10 > pick the tweak, or `.\pccleanup.ps1 -Undo "TweakName"`
- Undo everything: menu option 10 > Undo All, or `.\pccleanup.ps1 -Undo All`
- Nuclear option: use System Restore to roll back to the automatic restore point

## Is This Safe?

Don't trust me -- check it yourself. `pccleanup.ps1` is a single readable PowerShell file, and `config/tweaks.json` lists every registry key, service, and scheduled task the tool touches, with links to Microsoft's docs. Open either one in a text editor and you can see exactly what's going on.

Or just paste the script (or the JSON) into ChatGPT, Claude, Gemini, whatever, and ask if it does anything sketchy.

You can also run `.\pccleanup.ps1 -WhatIf` to preview every change without actually applying anything.

## What This Tool Does NOT Do

There's a whole category of "optimization" advice floating around that ranges from useless to actively harmful. Here's what PC Cleanup deliberately skips, and why:

- **Registry cleaning** -- Microsoft's official position is "don't." Malwarebytes calls it snake oil. Those thousands of "registry errors" that cleaners find? They don't affect performance. At all.
- **RAM boosting** -- These tools force Windows to dump its SuperFetch cache to disk, which sounds like "freeing memory" but actually makes your next app launch slower. Your OS already manages RAM better than a third-party tool can.
- **Driver installation** -- Way too risky for an automated tool. If your driver situation needs fixing, you want a human making those calls.
- **Disabling Windows Update** -- I know it's tempting. But your PC genuinely needs security patches.
- **Disabling Windows Defender** -- Same deal. You need an antivirus, and the one built into your OS is honestly pretty good these days.
- **Disabling UAC** -- Those prompts are annoying, I get it. But UAC is a real security boundary, not just a nag screen.
- **Disabling PageFile** -- The "I have 32GB of RAM so I don't need a page file" thing is a myth. The Windows memory manager uses the page file to move dormant pages around even when you have tons of free RAM. Disabling it causes out-of-memory crashes under load.
- **Disabling SysMain/SuperFetch** -- Another persistent myth, especially for SSD users. SysMain pre-loads frequently used DLLs into standby memory with essentially zero I/O cost on an SSD. Disabling it increases page faults.
- **Removing UWP/Appx packages** -- On Windows 11 24H2, removing certain packages breaks File Explorer (dark mode, tabs, XAML stuff). And once you remove a system package, getting it back is a nightmare. We're not touching this.
- **App installation** -- Not our lane. [WinUtil](https://github.com/ChrisTitusTech/winutil) does this really well already.
- **GUI** -- A graphical interface would undermine the whole "paste it into an AI to verify" model. The tool is a script on purpose.

## Troubleshooting

### "Windows protected your PC" (SmartScreen)

You skipped the unblock step. Go back to the ZIP file, right-click > Properties > check "Unblock" > OK, then extract it again.

### Script opens and immediately closes

Windows Defender's AMSI (Antimalware Scan Interface) sometimes flags PowerShell scripts that modify registry keys related to telemetry. The fix is to add the extracted folder to Defender's exclusion list:

1. Open Windows Security > Virus & threat protection > Manage settings
2. Scroll to Exclusions > Add or remove exclusions
3. Add the folder where you extracted PC Cleanup

### "Running scripts is disabled on this system"

`Run.bat` already handles this with `-ExecutionPolicy Bypass`. If you're running `pccleanup.ps1` directly instead, set the policy for your session first:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### A tweak didn't seem to work

Visual effects and taskbar tweaks sometimes need Explorer to restart before they're visible. The tool tries to notify the shell automatically, but if things look the same, try restarting Explorer or just rebooting.

### Boot time didn't improve after Full Tune-Up

Give it two reboots. The first boot after making changes is almost always slower than normal (Windows is reconfiguring things). Take your "after" snapshot on the second clean boot for an accurate comparison.

The boot time measurement uses Event ID 100 from Windows diagnostics when available, with a WMI fallback. If your privacy tweaks disabled diagnostic logging, the fallback measurement is less granular -- the tool will tell you which source it's using.

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

The config files ship as separate, readable files rather than being baked into the script. You can open `tweaks.json` and see exactly what every tweak does. Power users can modify it to customize their setup.

### Source (for developers)
```
src/
  core/           # Infrastructure: utility, system info, safety, tweak engine, undo, file ops
  handlers/       # Registry, service, scheduled task, script handlers
  modules/        # Feature modules (Quick Clean, Privacy Shield, etc.)
  ui/             # Interactive menu system
  main.ps1        # Entry point and CLI dispatch
config/           # JSON configuration files
tests/unit/       # Pester tests (mocked, no admin needed)
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

Ground-up rewrite. Same philosophy, completely new architecture:

- **Modular codebase** -- 20 source files organized by responsibility instead of one giant script
- **Data-driven tweaks** -- all 29 tweaks defined in JSON, not scattered across functions
- **Real undo** -- captures your actual system state at apply time, not hardcoded guesses at defaults
- **Privacy Shield** -- 20 privacy tweaks across 3 risk tiers, each with a Microsoft docs link
- **Performance Mode** -- 9 performance tweaks with automatic laptop/SSD detection
- **Full CLI** -- profiles, per-module targeting, risk levels, WhatIf dry-runs, snapshots
- **Security Check** -- read-only health report (Defender, firewall, SMBv1, pending updates)
- **System Report** -- before/after metrics with accurate boot time measurement
- **Disk Analysis** -- drive usage bars and recursive folder size breakdown
- **Network Reset** -- deliberately isolated from the optimization flow with heavy warnings
- **470+ unit tests** -- Pester 5, fully mocked, no admin privileges needed to run them
- **Clean lint** -- 0 PSScriptAnalyzer warnings
- **CI/CD** -- GitHub Actions running lint, tests, and build on every push

### v1.2 (2025)

The original. One big script that proved the concept and got some nice traction on Reddit. Basic cleanup, startup management, and privacy tweaks.

## How It's Built

This project is built with [Claude Code](https://claude.ai/claude-code) (Anthropic).

I used AI to build this. That's not a secret. The code is open source and fully auditable no matter how it was written. My style of learning is typing the code over myself, yes Claude writes it all but i ask questions along the way. 

## License

[MIT](LICENSE) -- do whatever you want with it.
