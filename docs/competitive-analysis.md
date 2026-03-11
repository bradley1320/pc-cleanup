# PC Cleanup v2 — Competitive Source Code Analysis

> Generated 2026-02-24 from deep source-code analysis of 5 open-source Windows optimization projects.
> This is a research document — no code was written or project structure created.

---

## Table of Contents

1. [Architecture Comparison](#1-architecture-comparison)
2. [Best Patterns to Steal](#2-best-patterns-to-steal)
3. [Telemetry/Privacy Master List](#3-telemetryprivacy-master-list)
4. [Undo/Revert Approaches Compared](#4-undorevert-approaches-compared)
5. [Build/Distribution Approaches](#5-builddistribution-approaches)
6. [What Should Change About Our Planned Approach](#6-what-should-change-about-our-planned-approach)

---

## 1. Architecture Comparison

### Overview Matrix

| Aspect | winutil | Win11Debloat | Sophia-Script | optimizerNXT | WindowsTelemetryBlocker |
|--------|---------|-------------|---------------|-------------|------------------------|
| **Language** | PowerShell + WPF XAML | PowerShell + WPF XAML | PowerShell (module) | C# (.NET 4.8) | PowerShell |
| **Total LOC** | ~16,600 (PS+JSON+XAML) | ~6,050 (PS+XAML) | ~30,700 (across all variants) | ~1,850 C# | ~10,000 |
| **Config format** | JSON (7 files) | JSON + .reg files (211 reg files) | PowerShell preset file | YAML (28 files) | JSON (profiles) |
| **Tweak definition** | Data (JSON) with code escape hatch | .reg files + switch params | Code (one function = one tweak) | Data (YAML) with handler dispatch | Code (module functions) |
| **UI** | WPF GUI (single XAML) | WPF GUI (4 XAML files) + CLI | None (preset file editing) | Console CLI only | Console CLI + GUI (v1.0) |
| **Undo support** | Yes (OriginalValue in JSON) | Yes (66 undo .reg files) | Yes (each function has -Enable) | No built-in undo | Yes (per-module rollback scripts) |
| **OS handling** | Mostly agnostic, metadata labels | MinVersion/MaxVersion per feature | Separate codebases per OS | Condition block per job | Single codebase |
| **Distribution** | Single compiled .ps1 | Multi-file repo + Get.ps1 downloader | Module (.psm1 + manifest) | Compiled .exe + signed YAML | Multi-file repo |
| **Admin elevation** | Auto-relaunches with -Verb RunAs | `#Requires -RunAsAdministrator` | `#Requires -RunAsAdministrator` | Requires admin (manual) | Validates + warns |
| **Signing/verification** | No | No | No | RSA-SHA256 per YAML file | No |
| **Localization** | No | No | Yes (12 languages) | No | No |

### Tweak Count by Project

| Project | Registry tweaks | Service tweaks | Scheduled tasks | App removals | Other |
|---------|----------------|---------------|-----------------|-------------|-------|
| winutil | 58 tweaks in JSON | Embedded in tweaks | Embedded in tweaks | 200+ apps via winget/choco | Windows features (28) |
| Win11Debloat | 77 reg files (~140 features) | Via registry only | Via registry only | 138 apps | Windows features |
| Sophia-Script | 130+ functions | Direct service control | Direct task control | AppX removal functions | Group Policy via LGPO |
| optimizerNXT | 28 YAML configs | Handler-based | Via exec commands | UWP handler | Hosts, startup, network |
| WindowsTelemetryBlocker | ~17 registry paths | 12 services | Planned (v1.0) | 22 apps | Monitoring/baselines |

---

## 2. Best Patterns to Steal

### Pattern 1: Data-Driven Tweak Definitions (from winutil)

**What**: Define tweaks as JSON data, not as code. Each tweak declares registry keys, services, scheduled tasks, and scripts — the engine interprets them uniformly.

**Why**: Adding a new tweak is a JSON edit, not a code change. Separation of "what to change" from "how to change it" makes the codebase dramatically easier to maintain.

**Concrete schema to adopt** (simplified from winutil's actual structure):

```json
{
  "DisableActivityHistory": {
    "name": "Disable Activity History",
    "description": "Erases recent docs, clipboard, and run history.",
    "category": "Privacy",
    "risk": "low",
    "registry": [
      {
        "path": "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\System",
        "name": "EnableActivityFeed",
        "value": 0,
        "type": "DWord",
        "originalValue": 1
      }
    ],
    "services": [],
    "scheduledTasks": [],
    "invokeScript": [],
    "undoScript": []
  }
}
```

**Key winutil insight**: The `"originalValue"` field stored alongside each registry entry is what makes undo trivial — no separate undo config needed.

### Pattern 2: OriginalValue-Based Undo (from winutil)

**What**: Every registry modification stores its `OriginalValue` in the same JSON entry. The undo engine simply reads the original value and writes it back. Special sentinel `"<RemoveEntry>"` means "delete this key to undo."

**Why**: This is far simpler than maintaining separate undo files (Win11Debloat's 66 .reg files) or writing mirror functions (Sophia-Script's 130+ -Enable variants). One data structure, one engine, both directions.

**The actual dispatch pattern** (from winutil's `Invoke-WinUtilTweaks`):

```powershell
if ($undo) {
    $registryField = "OriginalValue"
    $serviceField = "OriginalType"
    $scriptField = "UndoScript"
} else {
    $registryField = "Value"
    $serviceField = "StartupType"
    $scriptField = "InvokeScript"
}
```

### Pattern 3: Handler/Engine Architecture (from optimizerNXT)

**What**: A central engine dispatches to specialized handlers (RegistryHandler, ServiceHandler, ExecHandler, HostsHandler, etc.) based on what's present in the config entry.

**Why**: Clean separation of concerns. Each handler knows one thing. The engine just routes. New handler types can be added without touching existing code.

**Adopt for PC Cleanup v2**: Create a similar dispatch pattern in PowerShell:
- `Set-PCCleanupRegistry` — handles all registry operations
- `Set-PCCleanupService` — handles all service operations
- `Set-PCCleanupScheduledTask` — handles all task operations
- `Invoke-PCCleanupScript` — handles arbitrary script blocks

### Pattern 4: OS Version Gating per Feature (from Win11Debloat)

**What**: Each feature in `Features.json` has optional `MinVersion` and `MaxVersion` fields (Windows build numbers). Features outside the range are silently skipped.

**Why**: Single codebase handles Win10 and Win11 without if/else spaghetti. Far better than Sophia-Script's approach of maintaining 9 separate codebases.

**Example from Win11Debloat**:
```json
{
  "FeatureId": "EnableEndTask",
  "MinVersion": 22631,
  "MaxVersion": null
}
```

### Pattern 5: Risk Categorization (from multiple projects)

**What**: Categorize tweaks by risk level. winutil uses a `z__Advanced Tweaks - CAUTION` prefix to sort dangerous tweaks last. WindowsTelemetryBlocker uses Minimal/Balanced/Maximum profiles. Win11Debloat gates features by OS build.

**Adopt for PC Cleanup v2**: Add a `"risk"` field to each tweak: `"safe"`, `"moderate"`, `"advanced"`. Default mode only applies safe tweaks. Users explicitly opt into higher risk levels.

### Pattern 6: System Restore Point Before Changes (from Win11Debloat)

**What**: Automatically create a Windows System Restore Point before applying any changes. Check for recent restore points to avoid duplicates (24-hour window). Use timeout protection to prevent hanging.

**Why**: Safety net that requires zero additional code to restore from. Win11Debloat's implementation is clean and production-tested.

### Pattern 7: Build Script Pattern (from winutil)

**What**: `Compile.ps1` concatenates modular source files into a single self-contained `winutil.ps1`. Order: start.ps1 → functions/ → config/ (as embedded here-strings) → XAML → main.ps1.

**Why**: Develop in modular files, distribute as a single file. Users run one command. No module installation, no dependency management.

### Pattern 8: Registry Backup Before Modification (from WindowsTelemetryBlocker)

**What**: Export full HKLM registry to timestamped `.reg` file before any modifications. Store in `registry-backups/` directory.

**Why**: Belt-and-suspenders safety. Even if the JSON-based undo fails, users have a raw registry backup.

---

## 3. Telemetry/Privacy Master List

### Registry Keys — Consolidated from All 5 Projects

#### HKLM (System-Wide)

| Registry Path | Value Name | Apply Value | Undo Value | Source(s) | Risk |
|--------------|-----------|------------|-----------|-----------|------|
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection` | AllowTelemetry | 0 | 3 | ALL 5 | **Safe** |
| `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection` | MaxTelemetryAllowed | 1 | 3 | Sophia, Win11Debloat, WTB | Safe |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | EnableActivityFeed | 0 | 1 | winutil, Sophia, WTB | Safe |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\System` | PublishUserActivities | 0 | 1 | winutil, Win11Debloat, Sophia, WTB | Safe |
| `HKLM:\SOFTWARE\Microsoft\SQMClient\Windows` | CEIPEnable | 0 | 1 | WTB, Sophia | Safe |
| `HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting` | Disabled | 1 | 0 | WTB, Sophia | Safe |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search` | AllowCortana | 0 | 1 | WTB | Moderate |
| `HKLM:\SOFTWARE\Policies\Microsoft\Edge` | PersonalizationReportingEnabled | 0 | (remove) | Win11Debloat | Safe |
| `HKLM:\SOFTWARE\Policies\Microsoft\Edge` | DiagnosticData | 0 | (remove) | Win11Debloat | Safe |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot` | TurnOffWindowsCopilot | 1 | (remove) | optimizerNXT, Win11Debloat | Safe |
| `HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI` | DisableAIDataAnalysis | 1 | (remove) | optimizerNXT | Safe |
| `HKLM:\System\CurrentControlSet\Control\Session Manager\Power` | HibernateEnabled | 0 | 1 | winutil | Moderate |

#### HKCU (Per-User)

| Registry Path | Value Name | Apply Value | Undo Value | Source(s) | Risk |
|--------------|-----------|------------|-----------|-----------|------|
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo` | Enabled | 0 | 1 | ALL 5 | **Safe** |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy` | TailoredExperiencesWithDiagnosticDataEnabled | 0 | 1 | Win11Debloat, Sophia | Safe |
| `HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy` | HasAccepted | 0 | 1 | Win11Debloat | Safe |
| `HKCU:\Software\Microsoft\Input\TIPC` | Enabled | 0 | 1 | Win11Debloat | Safe |
| `HKCU:\Software\Microsoft\InputPersonalization` | RestrictImplicitInkCollection | 1 | 0 | Win11Debloat | Safe |
| `HKCU:\Software\Microsoft\InputPersonalization` | RestrictImplicitTextCollection | 1 | 0 | Win11Debloat | Safe |
| `HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore` | HarvestContacts | 0 | 1 | Win11Debloat | Safe |
| `HKCU:\Software\Microsoft\Personalization\Settings` | AcceptedPrivacyPolicy | 0 | 1 | Win11Debloat | Safe |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | Start_TrackProgs | 0 | 1 | Win11Debloat | Safe |
| `HKCU:\Software\Microsoft\Siuf\Rules` | NumberOfSIUFInPeriod | 0 | (remove) | Win11Debloat, Sophia, WTB | Safe |
| `HKCU:\Software\Microsoft\Siuf\Rules` | PeriodInNanoSeconds | (remove) | — | Win11Debloat, WTB | Safe |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Diagnostics\DiagTrack` | ShowedToastAtLevel | 1 | 3 | Sophia | Safe |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | SubscribedContent-310093Enabled | 0 | 1 | Sophia, Win11Debloat | Safe |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications` | GlobalUserDisabled | 1 | 0 | WTB | Moderate |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | TaskbarDa | 0 | 1 | WTB, Win11Debloat | Safe |
| `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | ShowCopilotButton | 0 | 1 | optimizerNXT | Safe |

### Services — Consolidated

| Service Name | Display Name | Source(s) | Risk Level |
|-------------|-------------|-----------|------------|
| DiagTrack | Connected User Experiences and Telemetry | ALL 5 | **Safe** — consensus across all projects |
| dmwappushservice | WAP Push Message Routing Service | winutil, Sophia, WTB, optimizerNXT | **Safe** |
| WerSvc | Windows Error Reporting | Sophia, WTB, Win11Debloat | **Safe** |
| MapsBroker | Downloaded Maps Manager | WTB | Safe |
| WSearch | Windows Search | WTB | **Moderate** — some users need indexing |
| PcaSvc | Program Compatibility Assistant | WTB | Moderate |
| WMPNetworkSvc | Windows Media Player Network Sharing | WTB | Safe |
| XblGameSave | Xbox Live Game Save | WTB | Safe (if no Xbox use) |
| XblAuthManager | Xbox Live Auth Manager | WTB | Safe (if no Xbox use) |
| lfsvc | Geolocation Service | WTB (monitor) | Moderate |
| OneSyncSvc | Sync Host | WTB (monitor) | Moderate |
| DoSvc | Delivery Optimization | WTB (monitor) | **Moderate** — affects Windows Update speed |

### Scheduled Tasks — Consolidated

| Task Path | Source(s) | Risk |
|----------|-----------|------|
| `\Microsoft\Windows\Customer Experience Improvement Program\Consolidator` | Sophia, Win11Debloat, optimizerNXT | Safe |
| `\Microsoft\Windows\Customer Experience Improvement Program\KernelCeipTask` | Win11Debloat | Safe |
| `\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip` | Sophia | Safe |
| `\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector` | Sophia, Win11Debloat | Safe |
| `\Microsoft\Windows\Application Experience\ProgramDataUpdater` | Sophia | Safe |
| `\Microsoft\Windows\Autochk\Proxy` | Sophia | Safe |
| `\Microsoft\Windows\Maps\MapsToastTask` | Sophia | Safe |
| `\Microsoft\Windows\Maps\MapsUpdateTask` | Sophia | Safe |
| `\Microsoft\Windows\ErrorDetails\QueueReporting` | Sophia | Safe |

### Processes Blocked (via IFEO)

| Process | Source | Notes |
|---------|--------|-------|
| CompatTelRunner.exe | optimizerNXT | Compatibility telemetry runner |
| DeviceCensus.exe | optimizerNXT | Hardware telemetry collector |

### Firewall Rules

| Rule | Source | Notes |
|------|--------|-------|
| DiagTrack group — Block outbound | Sophia | Blocks telemetry at network level |

---

## 4. Undo/Revert Approaches Compared

### Comparison Matrix

| Approach | Project | Complexity | Granularity | Reliability | Solo Dev Effort |
|----------|---------|-----------|-------------|------------|----------------|
| **OriginalValue in JSON** | winutil | Low | Per-entry | High | **Low** — one data structure |
| **Separate .reg undo files** | Win11Debloat | Medium | Per-feature | High | Medium — maintain 66+ files |
| **Mirror functions (-Enable)** | Sophia-Script | High | Per-function | High | **High** — write 2x functions |
| **Per-module rollback scripts** | WTB | Medium | Per-module | Medium | Medium |
| **No undo (YAML is one-way)** | optimizerNXT | None | N/A | N/A | None |

### Recommendation for PC Cleanup v2

**Use winutil's OriginalValue pattern.** Reasons:

1. **Lowest maintenance burden**: Undo data lives next to apply data. No separate files to keep in sync.
2. **Automatic consistency**: If you add a new registry entry to a tweak, you add its OriginalValue at the same time. Impossible to forget.
3. **Single engine**: The same `Set-PCCleanupRegistry` function handles both apply and undo — just reads a different field.
4. **Special cases handled**: Use `"<RemoveEntry>"` sentinel for "this key didn't exist before, delete it to undo."
5. **Script escape hatch**: `InvokeScript` and `UndoScript` arrays handle complex cases that can't be expressed as pure data.

**Additional safety layers to add:**
- System Restore Point before first change (from Win11Debloat)
- Registry backup export (from WindowsTelemetryBlocker)
- Change log with timestamps (what was actually changed, not just what was attempted)

---

## 5. Build/Distribution Approaches

### Comparison

| Project | Source Structure | Distribution Format | Build Tool |
|---------|----------------|-------------------|-----------|
| winutil | 87 .ps1 + 7 .json + 1 .xaml | Single `winutil.ps1` (~16K lines) | `Compile.ps1` — custom concatenation |
| Win11Debloat | 24 .ps1 + 211 .reg + 4 .xaml | Multi-file repo + `Get.ps1` downloader | None — runs from repo |
| Sophia-Script | 9 variants × (module + private funcs) | PowerShell module (.psm1 + .psd1) | None — standard PS module |
| optimizerNXT | 18 .cs files | Compiled .exe + signed YAML folder | MSBuild / Visual Studio |
| WTB | ~22 .ps1 modules | Multi-file repo | None — runs from repo |

### winutil's Build Script Deep Dive

The `Compile.ps1` pattern is the most relevant for PC Cleanup v2:

```
Assembly order:
1. scripts/start.ps1        → Version string, parameters, admin check
2. functions/**/*.ps1        → All functions (Get-ChildItem recursive)
3. config/*.json             → Embedded as $sync.configs.X = @'...'@ | ConvertFrom-Json
4. xaml/inputXML.xaml        → Embedded as $inputXML = @'...'@
5. scripts/main.ps1          → Entry point, UI initialization
```

Key technique: JSON configs are embedded as PowerShell here-strings and parsed at runtime:
```powershell
$sync.configs.tweaks = @'
{ "WPFTweakExample": { ... } }
'@ | ConvertFrom-Json
```

### Recommendation for PC Cleanup v2

**Adopt winutil's compile-to-single-file pattern** with simplifications:

1. **Develop** in modular files: `functions/`, `config/`, `ui/`
2. **Build** with a simple `Build.ps1` that concatenates in order
3. **Distribute** as a single `pccleanup.ps1` (or optionally a module)
4. **Skip** the module manifest approach (Sophia) — too much ceremony for a solo dev
5. **Skip** compiled exe (optimizerNXT) — PowerShell is more transparent and inspectable for a trust-sensitive tool

---

## 6. What Should Change About Our Planned Approach

Based on reading actual source code (not READMEs), here are concrete recommendations:

### 6.1 — Use JSON-Driven Tweaks, Not Function-Per-Tweak

**Original assumption**: Each tweak is a PowerShell function.
**What code reveals**: winutil proves that 90%+ of tweaks can be pure data (registry path + value + original value). Only complex tweaks need script escape hatches. This cuts code volume dramatically and makes the tweak catalog a configuration problem, not a coding problem.

**Action**: Define tweaks in `config/tweaks.json` with the winutil schema. Build a generic engine that processes them.

### 6.2 — Don't Maintain Separate Win10/Win11 Codebases

**What Sophia-Script shows**: Maintaining 9 separate codebases for OS variants is enormous effort. ~30,700 lines of code, most of it duplicated.
**What Win11Debloat shows**: A `MinVersion`/`MaxVersion` field per feature handles OS differences elegantly in a single codebase.

**Action**: Single codebase. Add `"minBuild"` and `"maxBuild"` to the tweak JSON schema. Skip tweaks outside the range.

### 6.3 — Store OriginalValue in Tweak Data, Not Separate Undo Files

**What Win11Debloat shows**: 66 separate undo .reg files is a maintenance burden — every tweak change requires updating two files.
**What winutil shows**: `OriginalValue` right next to `Value` in the same JSON entry is simpler and inherently consistent.

**Action**: Every registry entry in tweaks.json includes `"originalValue"`. The engine toggles direction based on a boolean.

### 6.4 — Categorize by Risk, Not Just by Feature Area

**What all projects show**: Every project has some form of "be careful with these" categorization, but it's inconsistent:
- winutil: `z__Advanced Tweaks - CAUTION` prefix hack
- Win11Debloat: MinVersion gating
- WTB: Minimal/Balanced/Maximum profiles
- Sophia: Comment warnings in preset file

**Action**: First-class `"risk"` field on every tweak: `"safe"`, `"moderate"`, `"advanced"`. Default mode = safe only. CLI flag `--risk moderate` or `--risk advanced` to unlock higher tiers.

### 6.5 — Build a Compile Script from Day 1

**What winutil shows**: The compile script is 60 lines and dramatically improves distribution.
**What Win11Debloat/WTB show**: Running from a cloned repo is friction for end users.

**Action**: Create `Build.ps1` early. Develop modularly, distribute as single file.

### 6.6 — Create System Restore Points Automatically

**What Win11Debloat shows**: Production-tested pattern with timeout protection and duplicate prevention. Only 20 lines of code.

**Action**: Before first modification, create a restore point. Include timeout protection (20 seconds). Check for recent restore points to avoid duplicates.

### 6.7 — Consider Signature Verification for Community Tweak Packs

**What optimizerNXT shows**: RSA-SHA256 signing of YAML configs prevents tampering. Their binary .sig format is well-designed.

**Action**: Not needed for v1, but design the JSON schema so it could support signed community tweak packs later. This means keeping tweak definitions as standalone files (not hardcoded).

### 6.8 — The Telemetry Consensus Set is Clear

**What all 5 projects agree on**: These targets are safe and should be in any "default" privacy mode:
- `DiagTrack` service: disable
- `AllowTelemetry` = 0 (or 1 for Home/Pro)
- `AdvertisingInfo\Enabled` = 0
- `PublishUserActivities` = 0
- `EnableActivityFeed` = 0
- `NumberOfSIUFInPeriod` = 0 (disable feedback prompts)
- CEIP scheduled tasks: disable

**Action**: These form the "safe" tier. Everything else gets `"moderate"` or `"advanced"` risk level.

### 6.9 — Don't Disable Services via Registry Only

**What Sophia-Script shows**: Use `Stop-Service` + `Set-Service -StartupType Disabled` directly, then add firewall blocking for the DiagTrack group. This is more thorough than Win11Debloat's registry-only approach.
**What Win11Debloat shows**: Registry-only service changes don't take effect until reboot.

**Action**: Use direct service management (`Stop-Service`, `Set-Service`) for immediate effect. Store original startup type in JSON for undo.

### 6.10 — App Removal is Functionally Irreversible — Be Honest About It

**What WindowsTelemetryBlocker explicitly states**: "No action for apps module (manual intervention required)."
**What Win11Debloat shows**: Handles both provisioned and user-installed AppX packages, but has no undo.

**Action**: App removal should be a separate, clearly-warned operation. Not part of the default "safe" tier. Warn users that removed apps must be manually reinstalled from the Microsoft Store. Consider a "list what would be removed" dry-run mode.

---

## Appendix A: Project Statistics Summary

| Metric | winutil | Win11Debloat | Sophia-Script | optimizerNXT | WTB |
|--------|---------|-------------|---------------|-------------|-----|
| Total LOC | ~16,600 | ~6,050 | ~30,700 | ~1,850 | ~10,000 |
| PS files | 87 | 24 | 99 | 0 | 22 |
| Config files | 7 JSON | 3 JSON + 211 .reg | 9 presets | 28 YAML + 28 .sig | 1 JSON |
| Functions | 84 | ~15 | 130+ per variant | 8 handler classes | 200+ |
| GitHub Stars | 30K+ | 13K+ | 8K+ | 1K+ | <1K |
| Active Dev | Very active | Active | Active | Active | Active |
| License | MIT | MIT | MIT | GPL-3.0 | MIT |

## Appendix B: Key File Paths for Reference

### winutil
- Tweak definitions: `config/tweaks.json`
- App catalog: `config/applications.json`
- Build script: `Compile.ps1`
- Tweak engine: `functions/private/Invoke-WinUtilTweaks.ps1`
- Registry handler: `functions/private/Set-WinUtilRegistry.ps1`
- Admin elevation: `scripts/start.ps1`

### Win11Debloat
- Feature metadata: `Assets/Features.json`
- App list: `Apps.json`
- Default settings: `DefaultSettings.json`
- Registry modifications: `Regfiles/*.reg`
- Undo registry files: `Regfiles/Undo/*.reg`
- Main orchestrator: `Win11Debloat.ps1`

### Sophia-Script
- Windows 11 module: `src/Sophia_Script_for_Windows_11/Module/Sophia.psm1`
- Windows 10 module: `src/Sophia_Script_for_Windows_10/Module/Sophia.psm1`
- Preset config: `src/Sophia_Script_for_Windows_11/Sophia.ps1`
- Private helpers: `src/*/Module/Private/*.ps1`
- Localizations: `src/*/Localizations/*/Sophia.psd1`

### optimizerNXT
- YAML tweaks: `yaml/*.yaml`
- Signature files: `yaml/*.yaml.sig`
- Engine: `optimizerNXT/Engine.cs`
- YAML data model: `optimizerNXT/YamlSpec.cs`
- Signature verifier: `optimizerNXT/Signing/YamlVerifier.cs`
- Registry handler: `optimizerNXT/Handlers/RegistryHandler.cs`

### WindowsTelemetryBlocker
- Main entry: `windowstelemetryblocker.ps1`
- Telemetry module: `modules/telemetry.ps1`
- Services module: `modules/services.ps1`
- Rollback scripts: `modules/*-rollback.ps1`
- Risk profiles: `v1.0/config/profiles.json`
- Registry monitor: `v1.0/monitor/registry-monitor.ps1`
