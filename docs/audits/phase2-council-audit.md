# Phase 2 Council Audit: Privacy Shield Module + Full Tweak Catalog

**Date:** 2026-02-24
**Reviewers:** Gemini, Grok, DeepSeek (all 3 responded)
**Focus:** Security review of Phase 2 implementation
**Status:** Complete -- all findings addressed

---

## Audit Scope

- 20 privacy tweaks in tweaks.json (10 safe, 7 moderate, 3 advanced)
- Script undo mechanism (TweakEngine + UndoManager)
- BlockTelemetryFirewall invokeScript/undoScript
- BlockTelemetryIFEO Debugger technique
- PrivacyShield.ps1 UI input handling
- Risk tier classification validation

---

## Unanimous Findings (All 3 Agreed)

### 1. Registry Paths and Values: CORRECT
All 20 tweaks use correct registry paths and values per Microsoft documentation.
defaultValues match standard OS out-of-box configurations.

### 2. Safe-Tier Tweaks: NO BREAKAGE
No safe-tier tweak was found to break essential Windows functionality.

### 3. Risk Tier Classification: APPROPRIATE
DiagTrack (moderate), Copilot (moderate), Recall (moderate), IFEO (advanced),
Firewall (advanced), DeliveryOptimization (advanced) -- all correctly classified.

### 4. UI Input Handling: SAFE
Regex `^[Ii]\s*(\d+)$` and `^\d+$` are not injectable. Integer casting prevents
PowerShell injection via the input buffer.

### 5. Firewall `-Service DiagTrack`: CORRECT APPROACH
Using `-Service DiagTrack` with `-Program svchost.exe` is the correct and safest
way to block a shared-process service without affecting others.

### 6. IFEO Will Trigger AV Alerts
MITRE ATT&CK T1546.012 -- all 3 reviewers confirmed this will be flagged.

---

## Critical Finding: Undo Script Injection

**Severity:** HIGH (privilege escalation vector)
**All 3 reviewers independently identified this.**

### Vulnerability
- `undo_log.json` lives in `%LOCALAPPDATA%` (user-writable)
- It stored raw PowerShell command strings from `undoScript`
- An attacker who can write to this file gets arbitrary code execution as admin
  when the user next runs an undo operation
- `[scriptblock]::Create()` has no sandboxing

### Resolution (IMPLEMENTED)
**Gemini's approach adopted:** Do not store raw commands in undo_log.json.
- TweakEngine now stores only `Type = 'Script'` marker (no UndoCommands field)
- UndoManager reads undoScript from tweaks.json (shipped read-only config) at undo time
- If tweaks.json is missing or tweak definition changed, undo warns gracefully

**Files changed:** `src/core/04-TweakEngine.ps1`, `src/core/05-UndoManager.ps1`
**Tests added:** Security verification that UndoCommands field is NOT in undo_log.json

---

## Gemini-Unique Finding: Hybrid Tweak Bug

**Severity:** MEDIUM (latent bug for future tweaks)

### Bug
The `elseif` in TweakEngine prevented registering Script undo markers for tweaks
that have BOTH declarative changes (registry/service/task) AND an undoScript.

### Resolution (IMPLEMENTED)
Changed logic: if a tweak has declarative changes AND undoScript, the Script marker
is appended to the allChanges array alongside registry/service/task changes.

**Files changed:** `src/core/04-TweakEngine.ps1`
**Tests added:** Hybrid tweak test verifying both Registry and Script change types registered

---

## DeepSeek Finding: IFEO taskkill.exe Behavior

**Severity:** LOW (documentation, not functional)

### Issue
When IFEO triggers, Windows launches: `taskkill.exe CompatTelRunner.exe [args]`
taskkill.exe cannot parse this (expects `/IM` flag syntax).

### Resolution
Gemini confirmed: the IFEO mechanism prevents the original process from launching
regardless of whether the debugger succeeds. taskkill.exe exits immediately (with
an error it silently discards), and the original telemetry process never runs.

**Action taken:** Updated detail text to explain the IFEO mechanism accurately
(debugger replacement, not process killing) and added prominent AV warning.

---

## Detail Text Improvements (IMPLEMENTED)

| Tweak | Change |
|-------|--------|
| BlockTelemetryIFEO | Explained IFEO mechanism; added explicit AV/EDR false positive warning |
| DisableCopilot | Added note that background processes may still run |
| DisableBackgroundApps | Added UWP notification/update/live tile impact |
| BlockTelemetryFirewall | Added note about executable path existence per Windows version |
| DisableDiagTrack | Fixed duplicate sentence in detail text |

---

## Risk Tier Reclassification: NO CHANGES

DeepSeek suggested several reclassifications (SetTelemetryRequired to moderate,
DisableWebSearch to safe, BlockTelemetryIFEO to critical, etc.).

**Decision: Keep current tiers.** Gemini and Grok agreed with all current
classifications. The spec explicitly places AllowTelemetry=1 in safe tier.
DeepSeek was the lone dissenter on all reclassification suggestions.

---

## Deferred to Future Work

| Item | Reason |
|------|--------|
| undo_log.json HMAC/signature | Mitigated by not storing commands; remaining risk is wrong undo values (low impact, System Restore Point is backup) |
| Firewall executable path validation at runtime | Rules with nonexistent paths have no effect (harmless); documented in detail text |
| Constrained language mode for ScriptHandler | Would break legitimate script operations; current security model (read from shipped config) is sufficient |
| Code signing for tweaks.json | Complex for an open-source ZIP distribution; SHA256 checksums in README are the planned approach |
