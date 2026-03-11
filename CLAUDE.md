# PC Cleanup v2 — CLAUDE.md Specification

## Current State
- **Done:** Phase -1.5 (Landscape Research), Phase -1 (Specification draft), Phase -0.5 (Council review — Grok, Gemini, DeepSeek — all 3 reviewed, feedback incorporated, spec finalized)
- **Next:** Phase 0 (Repo, Scaffold, CI)
- **Blocked:** Nothing
- **Timeline:** 4–6 months part-time (council consensus)

---

## Purpose

PC Cleanup is an open-source PowerShell Windows optimization toolkit. v1 was a single monolithic script that proved the concept and gained real traction on Reddit. v2 is a modular rewrite in the same repo, keeping the same philosophy: radical transparency, safety-first design, and the "paste into AI to verify" trust model.

**What it does:** Cleans junk files, optimizes performance settings, disables telemetry/tracking, checks security health, and proves its results with before/after metrics.

**Who it's for:** Everyone from power users to people who've never opened a terminal. The tool explains itself in plain English at every step.

**Why it matters:** The optimizer you can read, understand, and undo — one tweak at a time. Every change is explained, every change is reversible, and the code is designed to be pasted into AI for verification.

**Project type:** Product (open source, same repo as v1: bradley1320/pc-cleanup, private during v2 development, public on release)

**Distribution:** Download ZIP, right-click → Properties → check "Unblock" (strips Mark of the Web), extract, right-click Run.bat → Run as Administrator. Zero install, zero dependencies. The Unblock step is mandatory — without it, Windows SmartScreen and AMSI will block execution of unsigned scripts. README documents this prominently.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         User                                 │
│              Terminal UI  /  CLI Flags                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                    main.ps1                                   │
│            Entry point: UI loop, CLI parsing,                │
│            module loading, profile dispatch                   │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                  Tweak Engine                                 │
│     Reads tweaks.json → dispatches to handlers               │
│     Handles apply / undo direction via boolean               │
│     Enforces risk tier gating                                │
│     Enforces OS build gating (minBuild/maxBuild)             │
└──┬──────────┬──────────┬──────────┬─────────────────────────┘
   │          │          │          │
   ▼          ▼          ▼          ▼
┌──────┐ ┌────────┐ ┌────────┐ ┌────────┐
│ Reg  │ │Service │ │ Task   │ │Script  │
│Handle│ │Handler │ │Handler │ │Handler │
└──────┘ └────────┘ └────────┘ └────────┘
   │          │          │          │
   ▼          ▼          ▼          ▼
┌─────────────────────────────────────────────────────────────┐
│               Windows (Registry, Services, Tasks, FS)        │
└─────────────────────────────────────────────────────────────┘

Safety layers (applied before ANY change):
  1. System Restore Point (auto, with 24hr duplicate check — graceful fallback if disabled)
  2. Registry backup export (timestamped .reg file)
  3. Per-tweak state capture at apply time (current values stored in undo_log.json — NOT hardcoded)
  4. Change log with timestamps
```

### Data Flow

1. User selects action (menu or CLI flag)
2. Engine loads relevant tweaks from `tweaks.json`
3. Engine filters by risk tier (safe/moderate/advanced) and OS build
4. For cleanup operations: scan → preview → user selects → execute
5. For tweak operations: read current state → apply change → register undo
6. For read-only operations (security check, metrics): query → display

---

## Tech Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Language | PowerShell 5.1+ | Native on all Windows 10/11, zero install |
| Config format | JSON | Human-readable, tweak catalog as data not code (winutil pattern) |
| Testing | Pester 5.x | Standard PS testing framework |
| Build | Custom Build.ps1 | Concatenates modular source → single .ps1 for distribution (winutil pattern) |
| CI | GitHub Actions (Windows runner) | Pester tests + PSScriptAnalyzer linting |
| Distribution | ZIP (pccleanup.ps1 + Run.bat) | Zero install, zero dependencies |
| Version control | Git + GitHub | Same repo: bradley1320/pc-cleanup |
| License | MIT | Same as v1 |

---

## Project Structure

### Source (development)
```
pc-cleanup/
├── src/
│   ├── core/                              # Core infrastructure (loaded first)
│   │   ├── 01-Utility.ps1                 # Admin check, logging, Write-Success/Warn/Err, helpers
│   │   ├── 02-SystemInfo.ps1              # OS detection, SSD detection, chassis type, feature detection
│   │   ├── 03-SafetyNet.ps1               # System Restore Point, registry backup export
│   │   ├── 04-TweakEngine.ps1             # JSON loader, handler dispatch, risk/OS gating
│   │   └── 05-UndoManager.ps1             # Per-tweak undo registration, undo log, rollback
│   ├── handlers/                           # Type-specific handlers (called by engine)
│   │   ├── RegistryHandler.ps1            # Set-PCCleanupRegistry — apply/undo registry entries
│   │   ├── ServiceHandler.ps1             # Set-PCCleanupService — stop/start, change startup type
│   │   ├── TaskHandler.ps1                # Set-PCCleanupScheduledTask — enable/disable tasks
│   │   └── ScriptHandler.ps1              # Invoke-PCCleanupScript — escape hatch for complex ops
│   ├── modules/                            # Feature modules (UI-facing operations)
│   │   ├── QuickClean.ps1                 # Temp files, browser caches, recycle bin, WU cache
│   │   ├── StartupManager.ps1             # List/disable/enable with publisher, description, risk
│   │   ├── PerformanceMode.ps1            # Power plan, visual effects, gaming tweaks
│   │   ├── PrivacyShield.ps1              # Telemetry, tracking, ads — presents tweaks.json by category
│   │   ├── NetworkReset.ps1               # DNS flush, Winsock, TCP/IP — isolated with heavy warnings
│   │   ├── DiskAnalysis.ps1               # Recursive folder sizes, drive usage bars
│   │   ├── SecurityCheck.ps1              # Defender, firewall, SMBv1, update status (read-only)
│   │   ├── SystemReport.ps1               # Before/after metrics: boot time, processes, disk space
│   │   └── FullTuneUp.ps1                 # Orchestrates safe-tier cleanup + performance + privacy
│   ├── ui/
│   │   └── Menu.ps1                       # Banner, main menu, sub-menus, selection UI
│   └── main.ps1                           # Entry point: param parsing, module loading, UI launch
├── config/
│   ├── tweaks.json                        # All data-driven tweaks (privacy, performance, etc.)
│   ├── apps-bloat.json                    # Known bloatware startup programs (exclusion/warning list)
│   ├── apps-critical.json                 # Critical startup programs that should NOT be disabled
│   └── profiles.json                      # Preset profiles (Safe, Gaming, Privacy, Custom)
├── tests/
│   ├── unit/                              # Pester unit tests (mocked, no admin needed)
│   │   ├── TweakEngine.Tests.ps1
│   │   ├── RegistryHandler.Tests.ps1
│   │   ├── UndoManager.Tests.ps1
│   │   └── ...
│   └── integration/                       # Manual VM test scripts + checklist
│       └── README.md
├── docs/
│   └── competitive-analysis.md            # Phase -1.5 research output
├── build/
│   ├── Build.ps1                          # Concatenates source → dist/pccleanup.ps1
│   └── Run.bat                            # Launcher: powershell -ExecutionPolicy Bypass -File pccleanup.ps1
├── dist/                                  # Build output (single .ps1 + Run.bat) — .gitignored
├── .github/
│   ├── workflows/ci.yml                   # GitHub Actions: Pester + PSScriptAnalyzer + secrets scan
│   └── dependabot.yml                     # Not applicable (no package deps) — placeholder
├── .gitignore
├── CLAUDE.md                              # This file
├── README.md                              # User-facing docs (filled in Polish phase)
└── LICENSE                                # MIT
```

### Distribution (what users download)
```
pc-cleanup-v2.zip
├── pccleanup.ps1                          # Single compiled script (all source concatenated)
├── Run.bat                                # Right-click → Run as Administrator
└── config/
    ├── tweaks.json                        # Tweak catalog (user can inspect/modify)
    ├── apps-bloat.json                    # Bloatware list
    ├── apps-critical.json                 # Critical apps list
    └── profiles.json                      # Preset profiles
```

Config files ship separately (not compiled in) so users can inspect and modify them. This reinforces the transparency philosophy — the tweak catalog is readable data, not buried code.

---

## Module Specifications

### Core: 01-Utility.ps1
**Responsibility:** Shared helper functions used by all modules.
**Key functions:**
- `Test-IsAdmin` → returns bool
- `Write-Success`, `Write-Info`, `Write-Warn`, `Write-Err`, `Write-Skip` → colored console output
- `Write-Log` → append to session log file with timestamp
- `Get-UserConfirmation` → Y/N prompt with default
- `Pause-Script` → Press Enter to continue
- `Format-FileSize` → bytes to human-readable (KB/MB/GB)
**Dependencies:** None (this is the base layer)

### Core: 02-SystemInfo.ps1
**Responsibility:** Detect system capabilities using feature detection (not version checking).
**Key functions:**
- `Get-OSBuild` → returns Windows build number (for minBuild/maxBuild gating)
- `Test-IsSSD -DriveLetter C` → returns bool (via Get-PhysicalDisk MediaType)
- `Get-ChassisType` → Desktop/Laptop/Tablet (via Win32_SystemEnclosure)
- `Test-FeatureExists -RegistryPath <path> -ValueName <name>` → returns bool (feature detection pattern from Gemini analysis)
**Design principle:** Feature detection over version checking. Ask "does this registry key exist?" not "is this Windows 11?"

### Core: 03-SafetyNet.ps1
**Responsibility:** Create safety layers before any modifications.
**Key functions:**
- `New-SafetyRestorePoint` → creates System Restore Point with 24hr duplicate check, 20s timeout. **Graceful fallback:** If System Restore is disabled (by policy, low disk, or user), logs a warning and continues — does NOT abort. Falls back to registry backup as primary safety net.
- `Backup-RegistryHive -Path <hive> -OutputDir <dir>` → exports registry key to timestamped .reg file
- `Get-SafetyStatus` → returns summary of available restore points and backups
**When called:** Automatically before the first modification in any session. Not called for read-only operations.

### Core: 04-TweakEngine.ps1
**Responsibility:** Load tweaks.json, filter by risk/OS, dispatch to handlers.
**Key functions:**
- `Get-Tweaks -Category <string> -RiskLevel <string>` → returns filtered tweak objects from JSON
- `Invoke-Tweak -Name <string> -Undo:$false` → applies or undoes a single tweak
- `Invoke-TweakSet -Category <string> -RiskLevel <string> -Undo:$false` → applies/undoes all tweaks in a category at a risk level
**Dispatch logic (from winutil pattern):**
```
For each tweak entry:
  if NOT $Undo:
    → capture current state via Get-PCCleanupRegistryValue / Get-Service / etc.
    → store original state in UndoManager (Register-AppliedTweak)
    → apply target values from tweaks.json (value/startupType/invokeScript)
  if $Undo:
    → read original values from undo_log.json (NOT from tweaks.json)
    → restore original state

  if entry has "registry" → call Set-PCCleanupRegistry for each
  if entry has "services" → call Set-PCCleanupService for each
  if entry has "scheduledTasks" → call Set-PCCleanupScheduledTask for each
  if entry has "invokeScript" → call Invoke-PCCleanupScript for each
```
**Gating logic:**
- Skip if `risk` > current session risk level
- Skip if OS build < `minBuild` or > `maxBuild`
- Log skipped tweaks with reason
**Config validation (council-mandated):** On first load, validate tweaks.json against expected schema (required fields present, registry entries have `type` field, risk values are valid). If validation fails, exit with clear error: "tweaks.json is invalid. Please restore from original ZIP." Uses `Test-Json` where available, manual field checking as fallback.
**Path resolution:** All config file paths resolved via `Join-Path $PSScriptRoot "config"` — never relative to working directory.

### Core: 05-UndoManager.ps1
**Responsibility:** Track applied tweaks with full original state, enable per-tweak and bulk undo.
**Key functions:**
- `Register-AppliedTweak -Name <string> -Changes <array> -Timestamp <datetime> -Category <string>` → captures current system state for each change (registry values, service types, task states) and appends full undo record to log
- `Get-AppliedTweaks` → returns list of currently applied (undoable) tweaks with metadata
- `Invoke-UndoTweak -Name <string>` → undoes a single tweak using stored original values from undo log
- `Invoke-UndoAll` → undoes all applied tweaks in reverse order
**Storage:** `%LOCALAPPDATA%\PCCleanup\undo_log.json` — persists between sessions.
**Critical design (council-mandated):** The undo log stores the FULL original state captured at apply time — not hardcoded defaults from tweaks.json. This ensures correct undo even when the user had custom settings before running the tool. The `originalValue` field in tweaks.json is a documentation/fallback reference only, NOT the primary undo source.

**Undo log entry format:**
```json
{
  "TweakName": "DisableTelemetry",
  "AppliedAt": "2025-02-24T10:00:00Z",
  "AppliedOnBuild": 22631,
  "Category": "Privacy",
  "Changes": [
    {
      "Type": "Registry",
      "Path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\DataCollection",
      "Name": "AllowTelemetry",
      "OriginalValue": 1,
      "OriginalType": "DWord",
      "KeyExistedBefore": true
    },
    {
      "Type": "Service",
      "Name": "DiagTrack",
      "OriginalStartupType": "Automatic",
      "OriginalStatus": "Running"
    },
    {
      "Type": "ScheduledTask",
      "Path": "\\Microsoft\\Windows\\...",
      "OriginalEnabled": true
    }
  ]
}
```

**Edge cases:**
- Registry value didn't exist before → `"KeyExistedBefore": false` → undo removes the entry
- Service was already disabled → undo restores to disabled (not to hardcoded default)
- Undo log corruption → fall back to System Restore Point
- OS build changed since apply (Feature Update) → warn user: "This tweak was applied on build X. Current build is Y. Undo values may not match current OS defaults. Proceed?"

### Handlers: RegistryHandler.ps1
**Responsibility:** All registry read/write operations.
**Key functions:**
- `Set-PCCleanupRegistry -Path <string> -Name <string> -Value <object> -Type <string>` → creates key if missing, sets value, handles `<RemoveEntry>` sentinel for undo
- `Get-PCCleanupRegistryValue -Path <string> -Name <string>` → reads current value and type (for state capture at apply time)
**Safety:** All operations wrapped in try/catch. Logs every change.
**Critical: Strict type casting (council-mandated).** PowerShell 5.1's `ConvertFrom-Json` infers types loosely — a JSON integer may become `System.Int32` or `System.Double`, which `Set-ItemProperty` writes as REG_SZ (string) instead of REG_DWORD. The handler MUST explicitly cast based on the `"type"` field in tweaks.json:
- `"DWord"` → cast to `[UInt32]`, use `-Type DWord`
- `"QWord"` → cast to `[UInt64]`, use `-Type QWord`
- `"String"` → cast to `[string]`, use `-Type String`
- `"ExpandString"` → cast to `[string]`, use `-Type ExpandString`
- `"MultiString"` → cast to `[string[]]`, use `-Type MultiString`
- `"Binary"` → cast to `[byte[]]`, use `-Type Binary`

Never rely on PowerShell's default type inference for registry writes. A REG_DWORD written as REG_SZ will silently break the target service/feature.

**TrustedInstaller keys:** Some telemetry and Defender keys are owned by `NT SERVICE\TrustedInstaller`. Standard admin can't write to these. The handler catches `Access Denied` gracefully and logs: "This key is protected by TrustedInstaller. Use Group Policy instead." Does NOT attempt ACL manipulation (too fragile for a general-purpose tool).

### Handlers: ServiceHandler.ps1
**Responsibility:** Service start/stop and startup type changes.
**Key functions:**
- `Set-PCCleanupService -Name <string> -StartupType <string> -StopFirst:$true` → changes startup type, optionally stops service first
**Safety:** Uses `Stop-Service` + `Set-Service` for immediate effect (not registry-only, per Sophia Script finding). Validates service exists before operating. Catches `Access Denied` for protected services (some services restart automatically or deny modification even as admin) — logs warning and skips gracefully. Post-apply verification: checks that the service actually changed state (some protected services silently revert).

### Handlers: TaskHandler.ps1
**Responsibility:** Scheduled task enable/disable.
**Key functions:**
- `Set-PCCleanupScheduledTask -TaskPath <string> -Enabled <bool>` → enables or disables a scheduled task
**Safety:** Validates task exists. Only targets tasks in the safe/moderate/advanced lists from tweaks.json.

### Handlers: ScriptHandler.ps1
**Responsibility:** Execute arbitrary PowerShell script blocks (escape hatch for complex operations).
**Key functions:**
- `Invoke-PCCleanupScript -ScriptBlock <string>` → executes a script block defined in tweaks.json
**Safety:** Script blocks are stored as strings in JSON. This is the escape hatch for operations that can't be expressed as registry/service/task data (e.g., DISM cleanup, browser cache clearing).

### Module: QuickClean.ps1
**Responsibility:** Delete temporary/cache files with preview and user selection.
**Flow:**
1. Scan all cleanup targets (temp dirs, browser caches, recycle bin, WU cache, prefetch)
2. Display preview with file counts and sizes per target
3. User selects/deselects targets via checkbox menu
4. Execute cleanup only on selected targets
5. Display total space recovered
**Key functions:**
- `Get-CleanupTargets` → returns list of targets with sizes (read-only scan)
- `Invoke-Cleanup -Targets <array>` → deletes selected targets
- `Get-BrowserProfiles` → detects installed browsers and their profile paths (Chrome, Edge, Firefox, Brave, Opera, Arc)
**Browser detection:** Dynamic, not hardcoded paths. Checks standard install locations and enumerates profiles.
**Safety:** Checks for running browsers before attempting cache deletion. If browser is running, displays clear message: "Close [browser] before cleaning its cache for best results." Skips locked files silently. Never touches user documents, downloads, or personal files.

### Module: StartupManager.ps1
**Responsibility:** View and manage startup programs with context.
**Flow:**
1. Scan registry (HKCU + HKLM Run keys) and startup folder
2. For each entry: resolve file path → extract publisher, description from file properties
3. Cross-reference against apps-critical.json (warn) and apps-bloat.json (flag)
4. Display with risk indicators
5. User selects programs to disable/enable
**Key functions:**
- `Get-StartupPrograms` → returns list with Name, Publisher, Description, Path, Source (registry/folder), Risk
- `Disable-StartupProgram -Name <string>` → removes entry, registers undo
- `Enable-StartupProgram -Name <string>` → restores entry from undo data
**Safety:** Cross-references apps-critical.json. Shows "⛔ DO NOT DISABLE" for critical entries (audio drivers, GPU software, security tools). User can still override but must confirm. Handles orphaned startup entries (executable no longer exists) gracefully — displays "(file missing)" instead of crashing on FileVersionInfo lookup.

### Module: PrivacyShield.ps1
**Responsibility:** Present privacy/telemetry tweaks from tweaks.json organized by risk tier.
**Flow:**
1. Load tweaks from "Privacy" category in tweaks.json
2. Group by risk tier (safe/moderate/advanced)
3. Display with checkmarks, descriptions, and risk colors
4. User selects which to apply (default: all safe)
5. Dispatch to TweakEngine
**Key functions:**
- `Show-PrivacyMenu` → interactive display with tier grouping
- `Show-TweakInfo -Name <string>` → detailed explanation of one tweak (what, why, what might break, Microsoft docs link)
**Design:** This module is a thin UI wrapper around TweakEngine. All actual tweak definitions live in tweaks.json. Adding a new privacy toggle is a JSON edit.

### Module: PerformanceMode.ps1
**Responsibility:** Performance optimizations (power plan, visual effects, gaming).
**Flow:** Similar to PrivacyShield — loads "Performance" category from tweaks.json, presents by risk tier, dispatches to engine.
**Additional logic:**
- Detects laptop vs desktop via `Get-ChassisType` → warns about battery impact
- Detects SSD vs HDD via `Test-IsSSD` → skips HDD-specific tweaks on SSDs
- Power plan fallback logic (High Performance → Ultimate Performance → warn)
- **Explorer refresh (council-mandated):** After applying visual tweaks (transparency, context menus, taskbar changes), the Windows shell caches old values in memory. Changes won't be visible until the shell re-reads the registry. The module broadcasts `WM_SETTINGCHANGE` via P/Invoke, or as a fallback, offers to restart explorer.exe (`Stop-Process -Name explorer -Force; Start-Process explorer.exe`). Without this, users see no visual change and assume the tool is broken.

### Module: NetworkReset.ps1
**Responsibility:** Network troubleshooting (isolated from optimization flow).
**Key functions:**
- `Reset-DNSCache` → ipconfig /flushdns
- `Reset-WinsockCatalog` → netsh winsock reset (admin, requires reboot)
- `Reset-TCPIPStack` → netsh int ip reset (admin, requires reboot)
- `Clear-ARPCache` → netsh interface ip delete arpcache (admin)
**Safety:** NOT included in Full Tune-Up. Standalone troubleshooting tool. Displays explicit warning about VPN/Hyper-V/Docker/static IP impact before executing. Requires explicit user confirmation. After execution, prompts user to restart and warns that network connectivity will be temporarily lost until reboot.

### Module: DiskAnalysis.ps1
**Responsibility:** Show disk usage (read-only).
**Key functions:**
- `Get-DriveUsage` → drive usage bars with color coding (green/yellow/red)
- `Get-FolderSizes -Path <string> -Depth <int>` → recursive folder size analysis (default depth: 3)
**Safety:** Completely read-only. No modifications.

### Module: SecurityCheck.ps1
**Responsibility:** Security health snapshot (read-only).
**Key functions:**
- `Get-DefenderStatus` → enabled, signature age, real-time protection
- `Get-FirewallStatus` → all profiles (Domain, Private, Public)
- `Test-SMBv1Enabled` → check if SMBv1 is active
- `Get-PendingUpdates` → count of pending Windows updates
- `Get-SecurityReport` → aggregate all checks into summary with recommendations
**Safety:** Completely read-only. No modifications.

### Module: SystemReport.ps1
**Responsibility:** Before/after metrics collection and comparison.
**Key functions:**
- `Get-SystemSnapshot` → collects boot time (Event ID 100), process count, free disk space, startup program count
- `Save-SystemSnapshot -Label <string>` → saves snapshot to `%LOCALAPPDATA%\PCCleanup\snapshots\`
- `Compare-Snapshots` → loads before/after snapshots, displays delta table
**Boot time measurement:** Uses `Microsoft-Windows-Diagnostics-Performance/Operational` Event ID 100 for accurate phase-by-phase boot timing (MainPathBootTime + BootPostBootTime). Falls back to `LastBootUpTime` from `CIM_OperatingSystem` (WMI) if event log is unavailable.
**Important (council finding):** If PrivacyShield disables diagnostic performance logging, Event ID 100 will stop being generated. The CIM fallback is therefore essential for the "after" snapshot. Document this clearly in the comparison output: "Boot time source: Event ID 100" vs "Boot time source: WMI (less granular — diagnostic logging may be disabled by privacy tweaks)."
**User guidance:** Displays note that first reboot after changes may be slower. Recommends restarting twice before taking "after" snapshot.

### Module: FullTuneUp.ps1
**Responsibility:** Orchestrate safe-tier cleanup + performance + privacy in one flow.
**Flow:**
1. Create System Restore Point
2. Create registry backup
3. Take "before" snapshot
4. Run QuickClean (all targets, no user selection in auto mode)
5. Apply Performance tweaks (safe tier only)
6. Apply Privacy tweaks (safe tier only)
7. Apply Prefetch cleanup (admin only)
8. Run DISM component cleanup (admin only, with explicit warning: "This may take 5-15 minutes and requires a reboot. Component cleanup permanently removes superseded update packages — you will not be able to uninstall updates that shipped before this point." Requires separate confirmation.)
9. Display summary
10. Prompt to take "after" snapshot (after restart)
**Safety:** Only applies safe-tier tweaks. Does NOT include Network Reset. Creates automatic backup before any changes.

---

## Tweak JSON Schema

```json
{
  "TweakID": {
    "name": "Human-readable name",
    "description": "One-sentence description shown in menu",
    "detail": "Multi-sentence explanation: what it does, why you'd want it, what might break",
    "docsUrl": "https://learn.microsoft.com/...",
    "category": "Privacy | Performance | Cleanup",
    "risk": "safe | moderate | advanced",
    "minBuild": null,
    "maxBuild": null,
    "requiresAdmin": true,
    "registry": [
      {
        "path": "HKLM:\\...",
        "name": "ValueName",
        "value": 0,
        "type": "DWord",
        "defaultValue": 1
      }
    ],
    "services": [
      {
        "name": "ServiceName",
        "startupType": "Disabled",
        "defaultType": "Automatic"
      }
    ],
    "scheduledTasks": [
      {
        "path": "\\Microsoft\\Windows\\...",
        "enabled": false
      }
    ],
    "invokeScript": [],
    "undoScript": []
  }
}
```

**Field clarifications (council-revised):**
- `"value"` / `"startupType"` / `"enabled"` → the desired state when APPLYING the tweak
- `"defaultValue"` / `"defaultType"` → the standard Microsoft default for documentation and fallback. **NOT the primary undo source.** The actual original value is captured at apply time and stored in `undo_log.json` (see UndoManager). The `defaultValue` serves two purposes: (1) documentation — shows what Microsoft ships as default, (2) emergency fallback — if undo_log.json is corrupted or missing
- `"type"` → **mandatory** for registry entries. The RegistryHandler uses this for strict type casting (see RegistryHandler spec). Never omit this field.

**Special values:**
- `"value": "<RemoveEntry>"` → apply means delete this registry value
- `"defaultValue": "<NonExistent>"` → this key doesn't exist in a clean Windows install
- `invokeScript` / `undoScript` → arrays of PowerShell command strings for complex operations

---

## Key Design Decisions

### 1. JSON-Driven Tweaks Over Function-Per-Tweak
**Decision:** Define 90%+ of tweaks as JSON data, not PowerShell functions.
**Why:** winutil's source code proves this works at scale (58+ tweaks, all data-driven). Sophia Script's function-per-tweak approach produced 30,700 lines across 9 codebases. Adding a new tweak should be a JSON edit, not a pull request. The generic engine handles apply/undo for both directions.
**Trade-off:** Complex operations (browser cache clearing, DISM, disk analysis) still need script handlers. The `invokeScript`/`undoScript` escape hatch handles these.

### 2. Feature Detection Over Version Checking
**Decision:** Use `Test-Path` and `Test-FeatureExists` to probe for capabilities, never `if ($BuildNumber -ge 22000)`.
**Why:** Gemini's analysis showed that Windows 10/11 share the NT 10.0 kernel, build numbers branch unpredictably, and features get backported. Feature detection makes the tool forward-compatible with future Windows versions automatically.
**Implementation:** `minBuild`/`maxBuild` in JSON is a fallback for known OS-specific features, but the handlers themselves use feature detection.

### 3. Capture-at-Apply-Time Undo (Not Hardcoded Defaults)
**Decision:** When applying a tweak, capture the ACTUAL current system state and store it in undo_log.json. System Restore Point is a safety net, not the undo mechanism. The `defaultValue` in tweaks.json is documentation/fallback only.
**Why (council consensus — all 3 reviewers flagged this):** Hardcoded `originalValue` assumes every system starts from the same state. If a user already customized a setting, undo would overwrite their preference with a generic default. If tweaks.json is updated in a newer version, undo data for old tweaks becomes wrong. Capturing at apply time makes undo correct regardless of the user's starting state.
**Implementation:** The UndoManager stores a full record per tweak in undo_log.json: the type of each change (registry/service/task), the path/name, and the original value/state as it existed on THAT user's machine at apply time. Undo reads from this log, not from tweaks.json.

### 4. Config Files Ship Separately (Not Compiled In)
**Decision:** tweaks.json, apps-bloat.json, apps-critical.json, profiles.json ship as readable files in the ZIP, not embedded in the compiled .ps1.
**Why:** The transparency philosophy. Users (or AI verifiers) can read the tweak catalog without parsing PowerShell. Power users can modify the JSON to customize their setup. This is a differentiator — no other tool in the space makes its tweak definitions this inspectable.

### 5. Network Reset Isolated from Optimization
**Decision:** Network Reset is a standalone troubleshooting tool, NOT part of Full Tune-Up.
**Why:** Gemini's safety analysis showed that `netsh winsock reset` and `netsh int ip reset` destroy Hyper-V virtual switches, Docker networking, VPN configs, and static IP settings. v1 included this in the Full Tune-Up flow. v2 isolates it with explicit warnings.

### 6. No Snake Oil Features
**Decision:** PC Cleanup v2 explicitly does NOT include registry cleaning, RAM boosting, driver installation, Windows Update disabling, or Defender disabling.
**Why:** Registry cleaning is debunked (Microsoft says don't do it, Malwarebytes calls it snake oil). RAM "optimizers" force-flush SuperFetch cache and actively degrade performance. Disabling Defender/Update is a security risk. The README will explain WHY these are excluded — education is part of the product.

### 7. Risk Tiers with Default-Safe Philosophy
**Decision:** Every tweak has a risk level. Default mode only applies "safe" tweaks. Users must explicitly opt into "moderate" or "advanced."
**Why:** All 5 analyzed projects have some form of risk categorization, but none enforce it cleanly. The telemetry consensus from the competitive analysis (all 5 projects agree on the safe defaults) gives us a validated baseline.

### 8. CLI Flags for Automation
**Decision:** Support `.\pccleanup.ps1 -Profile Gaming -WhatIf` alongside the interactive menu.
**Why:** Grok's research showed sysadmins want automation-friendly, scriptable tools. CLI mode enables deploying across machines without interactive menus. `-WhatIf` (dry-run) builds trust by showing what WOULD happen.

---

## CLI Interface

```
.\pccleanup.ps1                              # Interactive menu (default)
.\pccleanup.ps1 -Profile Safe                # Apply all safe-tier tweaks
.\pccleanup.ps1 -Profile Gaming              # Gaming-optimized preset
.\pccleanup.ps1 -Profile Privacy             # Maximum privacy preset
.\pccleanup.ps1 -Module Privacy -Risk moderate  # Specific module + risk level
.\pccleanup.ps1 -WhatIf                      # Dry-run: preview all changes
.\pccleanup.ps1 -Undo All                    # Revert all applied tweaks
.\pccleanup.ps1 -Undo "DisableTelemetry"     # Revert specific tweak
.\pccleanup.ps1 -Report                      # Show system metrics
.\pccleanup.ps1 -Snapshot Before             # Take before snapshot
.\pccleanup.ps1 -Snapshot Compare            # Compare before/after
```

---

## Error Handling Philosophy

Every error tells the user:
1. **What happened** — in plain English, not a stack trace
2. **Why it happened** — the most likely cause
3. **What to do** — the specific next step

Example:
```
  [x] Could not disable DiagTrack service
      Why: Service is protected by Group Policy on this machine
      Fix: Run as Administrator, or check with your IT department
```

Errors never crash the script. All operations are wrapped in try/catch. Failed operations are logged and skipped — the script continues with remaining tasks.

---

## Distribution Security (Council Findings)

The ZIP distribution model conflicts with multiple Windows security layers. All three council reviewers flagged this.

### Mark of the Web (MotW) + SmartScreen
When a user downloads the ZIP via any browser, Windows applies an Alternate Data Stream (`Zone.Identifier`, `ZoneId=3`) to the file. Native Windows extraction propagates this tag to all extracted files. SmartScreen then blocks `Run.bat` with a full-screen blue warning ("Windows protected your PC") because the scripts are unsigned and lack reputation history.

**Mitigation:** README must prominently instruct: right-click ZIP → Properties → check "Unblock" → OK → THEN extract. This is step 1 of the install instructions, not a footnote.

### Antimalware Scan Interface (AMSI)
Even after bypassing SmartScreen, AMSI intercepts PowerShell script execution at the CLR level. If the script contains registry paths associated with telemetry modification, AMSI may silently terminate the process — the terminal window opens and immediately closes with no error.

**Mitigation:** Avoid modifying core Windows Defender keys (already in anti-goals). Avoid obfuscated strings. Include AMSI note in README troubleshooting section.

### Execution Policy
The `Run.bat` launcher uses `powershell -ExecutionPolicy Bypass -File pccleanup.ps1`. This overrides the user-level execution policy guardrail but does NOT bypass SmartScreen or AMSI. The Bypass flag is necessary and sufficient for its purpose — it is not a security boundary.

### SHA256 Checksums
Include SHA256 hashes of all config files in the README and optionally verify at launch. This detects version mismatch (user has old config with new script) and accidental corruption.

---

## Known Risks & Mitigations (Council Consensus)

Issues that WILL affect users in production, identified across all three reviews.

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Tweaks revert after Windows Feature Update | High | High | Document aggressively in README. Log applied tweaks with OS build. Warn on undo if build changed. Future work: re-apply scheduled task. |
| AV false positive on unsigned .ps1 | High | Medium | README includes Defender exclusion instructions + SHA256 checksums. |
| JSON parse/validation error | Medium | High | Schema validation in TweakEngine on load. Clear error message pointing to original ZIP. |
| Protected service Access Denied | Medium | Medium | Graceful catch + "Use Group Policy instead" message. Never attempt ACL manipulation. |
| Browser cache lock (browser running) | Medium | Low | Check for running browser processes. Skip locked files. Display "close browser for full cleanup" message. |
| Build.ps1 concatenation order wrong | Low | High | Document strict loading sequence: core (01→05) → handlers → modules. CI test verifies load order. |
| System Restore Point disabled | Medium | Medium | Graceful fallback to registry backup only. Warn but don't abort. |
| Event ID 100 missing after privacy tweaks | Medium | Low | CIM_OperatingSystem fallback. Label data source in comparison output. |
| Config/script version mismatch on update | Medium | Medium | Version header in config files. Launch-time version check. |
| TrustedInstaller-owned registry keys | Medium | Medium | Catch Access Denied, log clearly, skip gracefully. Do not attempt ownership changes. |
| Undo log stale after Feature Update | Medium | High | Store OS build in undo log. Warn user if build differs. Offer "restore Windows defaults" as alternative. |

---

## Implementation Phases

### Phase 0: Repo Setup, Scaffold, CI
**Gate type: verification (auto-advance if CI green)**

- Tag current v1 code as `v1.2` release
- Create `v2` branch
- Create full directory structure per Project Structure section
- Create Build.ps1 (concatenate source → single .ps1)
- Create Run.bat
- Create .gitignore (dist/, *.log, backups/)
- Create GitHub Actions CI workflow:
  - Trigger on push to any branch, PRs to main
  - Run PSScriptAnalyzer (linting)
  - Run Pester tests
  - Run secrets scan
  - Auto-create issue on failure
- Create stub files for all modules (empty functions with correct signatures)
- Build.ps1 produces valid (empty) pccleanup.ps1
- Initial commit and push to v2 branch

**Gate criteria:**
- [ ] v1.2 tag exists on main
- [ ] v2 branch exists with full directory structure
- [ ] Build.ps1 produces valid pccleanup.ps1
- [ ] CI workflow runs and passes (green)
- [ ] All stub files committed

### Phase 1: Core Infrastructure
**Gate type: decision (council audit: security review)**

Build the engine that everything else depends on.

- Implement 01-Utility.ps1 (all helper functions)
- Implement 02-SystemInfo.ps1 (OS build, SSD detection, chassis type, feature detection)
- Implement 03-SafetyNet.ps1 (System Restore Point, registry backup)
- Implement 04-TweakEngine.ps1 (JSON loader, handler dispatch, risk/OS gating)
- Implement 05-UndoManager.ps1 (undo log, register/rollback)
- Implement all 4 handlers (Registry, Service, Task, Script)
- Create initial tweaks.json with 5 test tweaks (mix of registry, service, task)
- Write Pester unit tests for engine and all handlers (mocked)
- Verify apply + undo cycle works end-to-end for all handler types

**Gate criteria:**
- [ ] TweakEngine loads and parses tweaks.json correctly
- [ ] All 4 handlers apply and undo correctly
- [ ] Risk gating filters tweaks correctly
- [ ] OS build gating filters tweaks correctly
- [ ] UndoManager persists and restores undo log across sessions
- [ ] SafetyNet creates restore point and registry backup
- [ ] All unit tests pass with >80% coverage
- [ ] CI green
- **Council audit:** Security review of handler implementations, especially registry writes and service management

### Phase 2: Privacy Shield Module + Full Tweak Catalog
**Gate type: decision (council audit: telemetry safety review)**

The headline new feature.

- Populate tweaks.json with full telemetry/privacy catalog from competitive analysis:
  - Safe tier: AllowTelemetry (set to 1/Required, not 0), AdvertisingInfo, ActivityHistory, CEIP tasks, Feedback, Error Reporting
  - Moderate tier: DiagTrack service, Cortana, background apps, location, search indexing, Copilot, Recall/AI
  - Advanced tier: Firewall rules, delivery optimization, IFEO blocks, hosts-file telemetry blocking
- **DiagTrack in moderate (council decision):** Gemini found that disabling the Connected User Experiences and Telemetry service breaks Xbox Live achievements, Game Pass connectivity, and Teredo tunneling. Each tweak detail must warn: "May affect Xbox achievements and Game Pass. Safe to disable if you don't use Microsoft gaming services."
- **Copilot/Recall in moderate (council decision):** On Windows 11 24H2, REMOVING Recall packages via DISM breaks File Explorer (dark mode, tabs, XAML dependencies). PC Cleanup NEVER removes packages — only disables via registry/GPO policy. Each tweak detail must state: "Disables via registry policy — does NOT remove packages. Package removal on 24H2 breaks File Explorer."
- Each tweak includes: name, description, detail (explanation), docsUrl, risk, defaultValue (Microsoft default for documentation)
- Implement PrivacyShield.ps1 (UI wrapper: tier grouping, selection, info display)
- Implement Show-TweakInfo (detailed per-tweak explanation)
- Write Pester tests for privacy tweaks (verify correct registry paths and values)
- Test apply + undo for every privacy tweak in VM

**Gate criteria:**
- [ ] All safe-tier privacy tweaks apply and undo correctly
- [ ] All moderate-tier privacy tweaks apply and undo correctly
- [ ] All advanced-tier privacy tweaks apply and undo correctly
- [ ] Show-TweakInfo displays correct detail and docs URL for each tweak
- [ ] Risk tier gating prevents moderate/advanced from applying in safe mode
- [ ] Unit tests pass
- [ ] CI green
- **Council audit:** Telemetry safety review — are we only using Microsoft-documented methods? Are defaultValues correct? Any risk of breaking Windows functionality? DiagTrack confirmed moderate? Copilot/Recall confirmed registry-only (no package removal)?

### Phase 3: Quick Clean + Startup Manager (v1 Upgrades)
**Gate type: verification (auto-advance)**

Rebuild v1's core features with v2 architecture.

- Implement QuickClean.ps1 with preview + user selection flow
- Implement dynamic browser detection (Chrome, Edge, Firefox, Brave, Opera, Arc + profiles)
- Implement StartupManager.ps1 with publisher, description, risk indicators
- Create apps-critical.json (audio drivers, GPU software, security tools)
- Create apps-bloat.json (known bloatware startup entries)
- Write Pester tests

**Gate criteria:**
- [ ] QuickClean shows preview with file counts and sizes
- [ ] User can deselect targets before cleanup
- [ ] All supported browsers detected with correct profile paths
- [ ] Browser cache skipped if browser is running
- [ ] StartupManager shows publisher, description for each entry
- [ ] Critical apps flagged with warning
- [ ] Bloatware apps flagged for easy identification
- [ ] Unit tests pass
- [ ] CI green

### Phase 4: Performance Mode + Security Check + System Report
**Gate type: verification (auto-advance)**

- Implement PerformanceMode.ps1 (loads from tweaks.json Performance category)
- Add performance tweaks to tweaks.json (power plan, visual effects, game mode, game bar, menu delay, transparency)
- Implement laptop/SSD detection warnings
- Implement SecurityCheck.ps1 (read-only health check)
- Implement SystemReport.ps1 (snapshots + comparison)
- Implement boot time measurement via Event ID 100
- Write Pester tests

**Gate criteria:**
- [ ] Performance tweaks apply and undo correctly
- [ ] Laptop warning displayed for power plan changes
- [ ] SSD detected correctly, HDD-specific tweaks skipped on SSD
- [ ] Security check displays Defender, firewall, SMBv1 status
- [ ] System snapshot captures boot time, process count, disk space
- [ ] Snapshot comparison displays correct deltas
- [ ] Unit tests pass
- [ ] CI green

### Phase 5: Full Tune-Up, Network Reset, Disk Analysis, CLI, Profiles
**Gate type: decision (requires approval)**

Wire everything together.

- Implement FullTuneUp.ps1 (orchestrate safe-tier across modules)
- Implement NetworkReset.ps1 (isolated, with warnings)
- Implement DiskAnalysis.ps1 (recursive scan, drive bars)
- Implement CLI parameter parsing in main.ps1
- Implement profiles.json and -Profile flag
- Implement -WhatIf dry-run mode (note: PowerShell's native ShouldProcess doesn't cover direct .NET calls or external commands. Build a simulation layer that logs intended changes via Write-Info without executing. Each handler needs a -WhatIf code path.)
- Implement Menu.ps1 (full interactive UI)
- Implement BackupRestore UI (list applied tweaks, per-tweak undo, undo all)
- End-to-end testing of full menu flow in VM

**Gate criteria:**
- [ ] Full Tune-Up runs all safe-tier optimizations in correct order
- [ ] Network Reset displays warnings and requires confirmation
- [ ] Disk Analysis shows recursive folder sizes
- [ ] CLI flags work: -Profile, -Module, -Risk, -WhatIf, -Undo, -Report, -Snapshot
- [ ] All profiles apply correct tweak sets
- [ ] -WhatIf logs intended changes without applying
- [ ] Interactive menu navigates all options correctly
- [ ] Backup & Restore shows applied tweaks, allows per-tweak undo
- [ ] All unit tests pass
- [ ] CI green

### Final Phase: Polish & Ship
**Gate type: decision (requires approval)**

- Fill in README.md:
  - What it is, prerequisites, install, configure, use
  - "Is This Safe?" section with AI verification instructions
  - "What This Tool Does NOT Do" section (registry cleaning, RAM boosting, etc.)
  - Per-module verification prompts for AI auditing
  - Screenshots
  - Changelog (v1.2 → v2.0)
- Verify works from clean clone (fresh extract from ZIP → Run.bat → working)
- No secrets in code
- Git history is clean conventional commits
- CI green on main
- Build.ps1 produces valid distribution ZIP
- Merge v2 branch to main
- Create v2.0 GitHub release with ZIP artifact

**Gate criteria:**
- [ ] README complete with all sections
- [ ] Clean clone test passes (fresh ZIP → Run.bat → all features work)
- [ ] No secrets in code (grep scan)
- [ ] CI green on main
- [ ] v2.0 release created on GitHub
- [ ] Current state updated to "Shipped"

---

## Future Work

These are explicitly deferred. Do NOT build during v2.0:

- **Hosts-file telemetry blocking** — advanced tier, reversible, backup original hosts file first. Common in WindowsTelemetryBlocker and Win11Debloat. Needs careful design to avoid breaking Microsoft Store/updates.
- **OneDrive disable/toggle** — common Reddit request. Mix of registry, scheduled tasks, folder operations. Needs careful testing for sync state.
- **Re-apply after update** — scheduled task to re-apply tweaks after Windows Feature Updates. #1 user complaint across all debloater tools. Needs build detection + selective re-apply.
- **Duplicate file finder** — scan directories, hash comparison, user selection
- **Scheduled task audit** — list all tasks with triggers, flag suspicious ones
- **App/UWP removal** — remove bloatware Appx packages (functionally irreversible, breaks Store on 24H2, needs careful design)
- **Community tweak packs** — signed JSON tweak files from community contributors
- **Deeper disk analysis** — WinDirStat-style visual treemap
- **Export security report** — HTML/PDF report for IT documentation
- **Localization** — multi-language support for non-English users

---

## Anti-Goals

These will NEVER be in PC Cleanup:

- ❌ Registry cleaning — snake oil, Microsoft says don't do it
- ❌ RAM boosting / memory freeing — placebo that degrades performance
- ❌ Auto-installing drivers — too risky, inform only
- ❌ Disabling Windows Update service — security risk
- ❌ Disabling Windows Defender — security risk
- ❌ Modifying Windows Update settings — beyond telemetry (pausing, active hours, etc.) is the user's domain
- ❌ Disabling or modifying UAC — lowers security posture, frequently requested but always harmful
- ❌ Modifying/disabling PageFile (pagefile.sys) — persistent myth that disabling helps with high RAM. In reality, the Windows memory manager relies on the page file to offload dormant pages and keep contiguous RAM available. Disabling causes OOM crashes under load.
- ❌ Disabling SysMain/SuperFetch — another persistent myth. On SSDs, SysMain intelligently preloads frequently used libraries into standby memory with near-zero I/O penalty. Disabling it increases hard page faults and degrades performance.
- ❌ Removing UWP/Appx packages — functionally irreversible, breaks Store, deeply tied to OS on 24H2. Deferred to future work with careful design.
- ❌ Hosts-file modification without backup/restore — if we add hosts blocking (advanced tier), it MUST backup the original hosts file and provide one-click restore
- ❌ App installation via winget/choco — WinUtil's domain, not ours
- ❌ ISO creation / MicroWin — WinUtil's domain, not ours
- ❌ GUI (WPF/WinForms) — kills the "paste into AI" transparency model
- ❌ Significant per-token API costs — no cloud dependencies

---

## Dev Principles (from Bootstrap Pipeline v4.2)

- Simple beats complex every time
- One feature at a time — no parallel work
- Test small before scaling
- Real-world testing over validation metrics
- Trust but verify all code — CI is the verify
- Mandatory stage gates — verification gates auto-advance, decision gates require approval
- Write down new ideas for later — don't add mid-phase
- If stuck debugging >4 hours, stop and take a break
- No scope creep — if it's not in the current phase, it waits
- No destructive actions without confirmation
- Never paste API keys into chat

### Comment Style (learned from v1 community feedback)
- **Explain WHY, not WHAT** — don't comment `# Get all running processes` above `Get-Process`. Do comment WHY you're checking for running processes before clearing cache.
- **No emoji in comments or code** — keep it professional
- **Write idiomatic PowerShell** — use built-in filtering (`Get-Process -Name $browsers`), avoid unnecessary variables and return statements, use `-Force` instead of test-then-create patterns
- **Comment-based help on every public function** — proper `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` blocks so `Get-Help` works
- **Use `Write-Verbose` for detailed output** — not `Write-Host` for everything. Power users control verbosity with `-Verbose` flag

### AI Transparency
This project is built with Claude Code (Anthropic) and designed in collaboration with Claude.ai. This is stated clearly in the README, the script header, and the repo description. AI-assisted development is how this project works — we don't hide it, we own it. The code is open source and fully auditable regardless of how it was written.

---

## Risk Tier Reference

Quick reference for tweak categorization. Each tweak's `risk` field in tweaks.json must match one of these tiers.

**Safe** (default mode — applied automatically in Full Tune-Up and Safe profile):
- AllowTelemetry set to 1 (Required diagnostic data, not 0)
- AdvertisingInfo disable
- ActivityHistory disable
- CEIP scheduled tasks disable
- Feedback frequency disable
- Error Reporting disable
- Visual effects optimization
- Power plan (High Performance)
- Game Mode / Game Bar toggles

**Moderate** (user must explicitly opt in — NOT applied in default/safe mode):
- DiagTrack service disable ⚠️ breaks Xbox achievements, Game Pass
- Cortana disable
- Background apps disable
- Location tracking disable
- Search indexing modifications
- Copilot disable (registry/GPO only, never package removal)
- Recall/AI disable (registry/GPO only, never package removal) ⚠️ package removal on 24H2 breaks File Explorer

**Advanced** (power users only — significant breakage potential):
- Windows Firewall outbound rules for telemetry endpoints
- Delivery Optimization disable (affects update speeds)
- IFEO blocks
- Hosts-file telemetry blocking (future work)

---

## Council Review Log

### Review Round 1 (Post-Spec Draft)
**Reviewers:** Grok, Gemini (Deep Research), DeepSeek
**Date:** February 2025
**Verdict:** All three approved the spec with required changes.

**Unanimous findings (all 3 agreed):**
1. Undo system must capture actual state at apply time, not use hardcoded originalValue
2. PowerShell 5.1 type casting requires strict enforcement in RegistryHandler
3. Mark of the Web / SmartScreen / AMSI will block execution — README must document Unblock step
4. System Restore Point may be disabled — must handle gracefully
5. Timeline is 4-6 months part-time, not 2 weeks

**Split decisions (resolved):**
- DiagTrack tier: Grok (safe) vs Gemini (moderate) vs DeepSeek (safe with warning) → **Moved to moderate** based on Gemini's Xbox/Game Pass evidence
- Copilot/Recall tier: Grok (safe) vs Gemini (dangerous on 24H2) vs DeepSeek (moderate) → **Moved to moderate**, registry-only (no package removal)
- Stateful vs stateless undo: Gemini (stateless defaults) vs Grok/DeepSeek (stateful capture-at-apply) → **Capture-at-apply-time wins** — stateless defaults have the same problem (wrong after Feature Update)

**Unique insights incorporated:**
- From Gemini: Explorer shell refresh after visual tweaks, Event ID 100 / telemetry interaction, TrustedInstaller ACL handling, PageFile and SysMain anti-goals, PS 5.1 JSON type inference deep dive, AMSI interception risk, 24H2 Recall/XAML dependency
- From Grok: Hosts-file blocking as future work, OneDrive toggle as future work, SHA256 checksums, AV false positive documentation, post-update re-apply prominence
- From DeepSeek: Config validation on startup, $PSScriptRoot path resolution, orphaned startup entry handling, WhatIf simulation layer, DISM cleanup warning