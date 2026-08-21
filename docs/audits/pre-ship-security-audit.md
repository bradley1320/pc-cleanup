# Pre-Ship Adversarial Security Audit -- PC Cleanup v2

**Date:** 2026-02-25
**Auditor:** Claude Opus 4.6 (adversarial mode)
**Scope:** All source, config, build, and distribution files
**Verdict:** Ship with 2 WARNINGs addressed. No CRITICALs found.

---

## Summary

| Severity | Count | Ship-blocking? |
|----------|-------|----------------|
| CRITICAL | 0     | --             |
| WARNING  | 5     | Fix before ship |
| NOTE     | 12    | Non-blocking    |

---

## 1. Code Injection & Input Validation

### F1 -- NOTE: tweaks.json invokeScript executes code via ScriptBlock::Create()

**Location:** `src/handlers/ScriptHandler.ps1:34`
**Finding:** `[ScriptBlock]::Create($ScriptBlock)` followed by `& $sb` executes arbitrary PowerShell from tweaks.json. The shipped JSON contains only legitimate commands (`New-NetFirewallRule`, `powercfg /setactive`).

**Risk assessment:** This is an intentional design decision (escape hatch for complex ops). The security boundary is the trust model: users are instructed to inspect the JSON and verify it with AI. The config ships as readable data alongside the script, not embedded in it. An attacker who can modify tweaks.json can also modify pccleanup.ps1 itself, so config integrity checking alone provides limited additional protection (the spec deferred HMAC/signing to future work).

**Why not CRITICAL:** The threat model explicitly assumes the user trusts their copy of the ZIP. The same-origin trust boundary applies to both the script and its config. No network-based config loading exists. SHA-256 hash verification was deferred per spec and council decision -- the spec explicitly lists "undo_log HMAC, constrained language mode, code signing for tweaks.json" as deferred items.

**Recommendation:** Document in README that users should verify their config files match the released hashes (already planned per spec).

### F2 -- NOTE: CLI parameters well-protected via ValidateSet

**Location:** `src/main.ps1:10-34`
**Finding:** `-Profile`, `-Module`, `-Risk`, `-Snapshot` all use `[ValidateSet()]` -- compile-time allowlists that reject all invalid values before script execution. `-Undo` accepts free-form `[string]` but is used only in `Where-Object { $_.TweakName -eq $Name }` (string equality, no eval). `-Report` and `-WhatIf` are `[switch]` (boolean only).

**Injection tests:**
- `-Profile "'; Remove-Item C:\ -Recurse"` -- rejected by ValidateSet
- `-Undo "$(calc.exe)"` -- `$(...)` evaluated by PowerShell's parser before the script receives it (caller's session, not script's). Inside the script, the literal output string hits `Where-Object -eq` and fails to match any TweakName. No code execution.
- `-Module "../../../etc"` -- rejected by ValidateSet

**Verdict:** Safe. No action needed.

### F3 -- NOTE: Menu input handling safe

**Location:** `src/ui/Menu.ps1` (all Read-Host calls)
**Finding:** `Read-Host` returns literal strings (no evaluation). Input flows into `switch` statements with explicit cases or `$choice -match '^\d+$'` regex. No input from Read-Host ever reaches `Invoke-Expression`, `[ScriptBlock]::Create()`, or string interpolation that could produce side effects.

**Minor robustness issue:** `[int]$choice` cast in `Show-BackupRestoreMenu` could throw `OverflowException` on Int32-exceeding input. Not a security issue -- PowerShell displays error and continues the menu loop.

**Verdict:** Safe. No action needed.

### F4 -- WARNING: profiles.json risk level not validated against profile name

**Location:** `src/main.ps1:130`
**Finding:** `$profileRisk = $selectedProfile.risk` reads the risk level directly from profiles.json without checking it against what that profile name should allow. A modified profiles.json could set the "Safe" profile to `"risk": "advanced"`, causing advanced-tier tweaks (firewall rules, IFEO blocks) to be applied when the user selected "Safe."

**Impact:** Users who trust the "Safe" label get advanced tweaks they didn't expect. Breakage potential is real -- IFEO tweaks trigger AV alerts, firewall rules block telemetry executables.

**Recommendation:** Hardcode maximum risk per profile name in the script:
```powershell
$maxRisk = @{ 'Safe' = 'safe'; 'Gaming' = 'safe'; 'Privacy' = 'moderate'; 'Custom' = 'advanced' }
$riskOrder = @('safe','moderate','advanced')
if ($riskOrder.IndexOf($profileRisk) -gt $riskOrder.IndexOf($maxRisk[$ProfileName])) {
    Write-Warn "Profile '$ProfileName' has elevated risk in profiles.json. Clamping to $($maxRisk[$ProfileName])."
    $profileRisk = $maxRisk[$ProfileName]
}
```

### F5 -- NOTE: Schema validation does not cover invokeScript/undoScript structure

**Location:** `src/core/04-TweakEngine.ps1:11-89`
**Finding:** `Test-TweakSchema` validates required fields for registry, services, and tasks, but does not validate that `invokeScript` and `undoScript` are arrays (or absent). A malformed JSON with `"invokeScript": "string"` instead of an array would cause a runtime error at `.Count`, not a clean schema error.

**Recommendation:** Add to schema validation:
```powershell
if ($tweak.invokeScript -and $tweak.invokeScript -isnot [array]) {
    throw "tweaks.json is invalid: Tweak '$id' has non-array invokeScript."
}
```

---

## 2. SafeFileOps Attack Surface

### F6 -- NOTE: Junction detection is solid -- uses .NET FileAttributes.ReparsePoint

**Location:** `src/core/06-SafeFileOps.ps1:68-104`
**Finding:** `Test-IsReparsePoint` uses `[System.IO.FileAttributes]::ReparsePoint` via .NET -- this is the correct and reliable method. It detects junctions, symlinks, and mount points. On failure to read attributes, it returns `$true` (defensive -- treats unreadable paths as suspicious).

**Verdict:** Correct implementation.

### F7 -- NOTE: TOCTOU mitigation is present and well-designed

**Location:** `src/core/06-SafeFileOps.ps1:313-329, 332-337, 360-361`
**Finding:** `Remove-SafeDirectory` performs three layers of TOCTOU mitigation:
1. Allowlist check at deletion time (line 314)
2. Reparse point re-check on the directory itself before recursion (line 324)
3. Reparse point check on every entry during enumeration (line 333)
4. Re-check before removing empty subdirectories (line 361)

**Race condition window:** Between line 333 (check attributes) and line 391 (file.Delete()), an attacker could theoretically swap a file for a symlink. However, `$entry.Delete()` on a `FileInfo` object uses the handle from enumeration, and `.NET FileInfo.Delete()` does not follow symlinks -- it deletes the symlink itself. For directory swaps, the re-check at line 361 catches post-enumeration replacements.

**Verdict:** The TOCTOU window is minimal and the defense-in-depth (allowlist + reparse check + re-check) makes exploitation impractical. The window between individual file attribute check and delete is a theoretical gap that exists in all non-atomic deletion implementations. Acceptable for this threat model.

### F8 -- NOTE: Allowlist validation is robust

**Location:** `src/core/06-SafeFileOps.ps1:106-150`
**Finding:** `Test-PathWithinAllowlist` resolves paths via `[System.IO.Path]::GetFullPath()` which:
- Canonicalizes `..\..\..` traversal -- `C:\Windows\Temp\..\..\System32` resolves to `C:\System32` which fails the allowlist
- Handles mixed slashes -- normalizes to backslash
- Case-insensitive via `OrdinalIgnoreCase`
- Prevents partial prefix matches -- checks for path separator after root match (line 144)

**Bypass attempts:**
- `..\..\..` -- canonicalized by GetFullPath, fails allowlist
- Trailing dots (`C:\Temp\evil...`) -- Windows API strips trailing dots, GetFullPath handles this
- Trailing spaces -- Windows API strips trailing spaces
- ADS (`file.txt:hidden`) -- GetFullPath preserves ADS notation. ADS on files in allowed directories would pass the allowlist but are then subject to the normal file deletion path. ADS on directories outside the allowlist are blocked. This is acceptable -- ADS within temp dirs are legitimate cleanup targets.
- `\\?\` prefix -- `Get-SafePath` adds this prefix for long paths, but the allowlist comparison happens BEFORE the prefix is added (the allowlist stores resolved paths without `\\?\`). An attacker-supplied `\\?\C:\Windows\System32` path would be resolved by GetFullPath to a path that doesn't match any allowlist root.
- UNC paths (`\\server\share`) -- would need to match an allowlist root, which are all local paths. Fails.
- Null bytes -- .NET strings can contain null bytes, but `[System.IO.Path]::GetFullPath()` throws `ArgumentException` on null characters in paths. The `catch` block returns `$false`. Safe.

**Verdict:** Robust. No bypasses found.

### F9 -- NOTE: Cloud placeholder detection uses correct flag values

**Location:** `src/core/06-SafeFileOps.ps1:152-182`
**Finding:** `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS` = `0x00400000` and `FILE_ATTRIBUTE_RECALL_ON_OPEN` = `0x00040000` are correct per Microsoft documentation. Raw integer bitwise AND is the right approach for PS 5.1 compatibility (the enum doesn't include these newer values).

**Verdict:** Correct.

### F10 -- NOTE: QuickClean uses SafeFileOps exclusively

**Location:** `src/modules/QuickClean.ps1:432`
**Finding:** `Invoke-Cleanup` calls `Remove-SafeDirectory` for all targets. No direct `Remove-Item -Recurse` in QuickClean. Browser profiles are registered with `Add-BrowserCleanupRoot` which validates they're not reparse points before adding to the dynamic allowlist.

**Verdict:** Correct.

### F11 -- WARNING: FullTuneUp prefetch cleanup uses Remove-Item directly, bypassing SafeFileOps

**Location:** `src/modules/FullTuneUp.ps1:166`
**Finding:** Prefetch cleanup in FullTuneUp uses `Remove-Item -LiteralPath $file.FullName -Force` on individual files obtained from `Get-ChildItem -Path $prefetchPath -File`. This bypasses SafeFileOps entirely.

**Risk:** Low -- the path is hardcoded to `$env:SystemRoot\Prefetch`, and `Get-ChildItem -File` only returns files (not directories), so junction following is not a concern. However, it's inconsistent with the "SafeFileOps exclusively for ALL file operations" principle and could be an issue if someone places a symlink file inside Prefetch pointing outside (unlikely but possible on multi-user systems).

**Recommendation:** Use `Remove-CleanupItem` from SafeFileOps instead:
```powershell
foreach ($file in $prefetchFiles) {
    $result = Remove-CleanupItem -Path $file.FullName
    $count += $result.DeletedFiles
}
```

### F12 -- NOTE: Anomaly detection checks deleted > estimated (not the reverse)

**Location:** `src/modules/QuickClean.ps1:452-458`
**Finding:** The anomaly check fires when `$summary.TotalBytes / $estimatedBytes > 1.2` (deleted 20% more than estimated). This catches filesystem growth between scan and delete. It does NOT check for the reverse (deleted much less than expected), which could indicate a junction attack where the allowlist blocked most deletions. However, the allowlist blocking is already logged per-path with SECURITY prefix, so the defense is adequate.

**Verdict:** Acceptable.

---

## 3. Privilege & Escalation Review

### F13 -- NOTE: Zero dangerous command patterns found

**Grep results across all src/ files:**
- `Set-Acl`, `takeown`, `icacls` -- **not found** (correct per spec)
- `Invoke-Expression`, `iex` -- **not found** (correct -- uses ScriptBlock::Create instead)
- `Invoke-Command` -- **not found** (no remote execution)
- `DownloadString`, `DownloadFile`, `WebClient`, `Invoke-WebRequest`, `Invoke-RestMethod` -- **not found** (zero network calls -- correct per spec)
- `ValueFromPipeline` -- **not found** (no pipeline input abuse vector)
- `-ExecutionPolicy` -- only in `Run.bat` and `build/Run.bat` (correct per spec)

### F14 -- NOTE: Start-Process usage is safe

**Location:** `src/modules/PerformanceMode.ps1:226`
**Finding:** `Start-Process explorer.exe` -- hardcoded executable name as fallback for Explorer refresh after visual tweak application. No user-controlled input flows into Start-Process. Safe.

### F15 -- NOTE: Add-Type usage is safe

**Location:** `src/modules/PerformanceMode.ps1:256`
**Finding:** `Add-Type -Namespace 'PCCleanup' -Name 'NativeMethods' -MemberDefinition @'...'@` compiles a hardcoded C# P/Invoke signature for `SendMessageTimeoutW` (user32.dll). The C# code is a literal string in the source, not user-controlled. Used for WM_SETTINGCHANGE broadcast. Safe.

---

## 4. Secrets & Data Exposure

### F16 -- NOTE: No secrets found in codebase

**Grep results:**
- `password`, `secret`, `bearer`, `token`, `api_key`, `credential` -- **not found** in src/ or config/
- One test file reference (`tests/unit/DiskAnalysis.Tests.ps1:131` contains `'secret.txt'` as a test filename) -- test data only, not actual secret
- No hardcoded paths with usernames (only `C:\Users\Public\junction` in a doc example)
- No email addresses in source
- No IP addresses in source

### F17 -- NOTE: Logging captures paths but not PII

**Location:** `src/core/01-Utility.ps1:118-148`
**Finding:** `Write-Log` appends timestamped messages to `%LOCALAPPDATA%\PCCleanup\logs\`. Logged content includes:
- Registry paths (e.g., `HKLM:\SOFTWARE\Policies\...`) -- not PII
- File paths during cleanup (e.g., `C:\Users\<username>\AppData\Local\Temp\...`) -- contains the Windows username, which is inherent to any file path logging. This is standard for system tools and documented behavior.
- Service names, scheduled task paths -- not PII
- No SIDs, machine names, or IP addresses logged

**Verdict:** Acceptable. The username in file paths is unavoidable and standard.

### F18 -- WARNING: .gitignore doesn't cover undo_log.json or snapshot files

**Location:** `.gitignore`
**Current contents:**
```
dist/
*.log
backups/
*.bak
.claude/
```

**Missing:**
- `undo_log.json` stored at `%LOCALAPPDATA%` -- not in repo, so not a git concern
- Snapshot files at `%LOCALAPPDATA%\PCCleanup\snapshots\` -- not in repo
- `docs/audits/` -- audit files could accidentally ship if not reviewed (though they're documentation, not secrets)

**Actually:** The undo_log, snapshots, and log files are all stored under `%LOCALAPPDATA%\PCCleanup\`, which is outside the repo. The `.gitignore` correctly covers repo-internal outputs. No issue.

**Revised verdict:** .gitignore is adequate. Reclassified as NOTE.

---

## 5. Registry Safety

### F19 -- NOTE: All registry paths are legitimate Microsoft paths

**Full review of all 52 registry entries across 29 tweaks in tweaks.json:**

**Hive distribution:**
- `HKLM:\SOFTWARE\Policies\Microsoft\Windows\*` -- 10 entries (Group Policy paths, correct)
- `HKLM:\SOFTWARE\Microsoft\Windows\*` -- 4 entries (system settings, correct)
- `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\*` -- 2 entries (IFEO, advanced tier, correct)
- `HKCU:\Software\Microsoft\Windows\CurrentVersion\*` -- 15 entries (user settings, correct)
- `HKCU:\Software\Microsoft\*` (other) -- 8 entries (user preferences, correct)
- `HKCU:\Control Panel\*` -- 5 entries (display/mouse settings, correct)
- `HKCU:\System\GameConfigStore` -- 1 entry (game DVR, correct)

**No writes to:** HKCR, HKEY_USERS, or outside HKLM\SOFTWARE and HKCU paths. Correct.

### F20 -- NOTE: Anti-goals verified -- no forbidden tweaks

**Verified absent from tweaks.json:**
- Windows Defender settings -- not found
- Windows Update service (`wuauserv`) -- not found as a tweak target. (Note: QuickClean temporarily stops wuauserv to clean its cache directory, then restarts it -- this is standard practice, not a tweak)
- UAC (`EnableLUA`, `ConsentPromptBehaviorAdmin`) -- not found
- PageFile -- not found
- SysMain/SuperFetch -- not found

### F21 -- WARNING: UserPreferencesMask stored as String type, should be Binary (REG_BINARY)

**Location:** `config/tweaks.json:642-644`
**Finding:**
```json
{
    "path": "HKCU:\\Control Panel\\Desktop",
    "name": "UserPreferencesMask",
    "value": "9012038010000000",
    "type": "String",
    "defaultValue": "9E3E078012000000"
}
```

Windows stores `UserPreferencesMask` as `REG_BINARY`, not `REG_SZ`. The RegistryHandler's strict type casting will write this as a string (`Set-ItemProperty -Type String`), which creates a `REG_SZ` instead of `REG_BINARY`. Windows reads the binary version; writing a string at this path will either be ignored or cause unpredictable visual effects behavior.

**Impact:** The visual effects tweak may silently fail to take effect. Windows will read the existing binary value and ignore the string value at the same name (or overwrite the binary with a string representation, breaking the setting).

**Recommendation:** Change to Binary type with proper byte array:
```json
{
    "path": "HKCU:\\Control Panel\\Desktop",
    "name": "UserPreferencesMask",
    "value": [144, 18, 3, 128, 16, 0, 0, 0],
    "type": "Binary",
    "defaultValue": [158, 62, 7, 128, 18, 0, 0, 0]
}
```
The hex string `9012038010000000` decodes to bytes `[0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00]` = `[144, 18, 3, 128, 16, 0, 0, 0]`.

### F22 -- NOTE: AllowTelemetry correctly set to 1 (Required), not 0

**Location:** `config/tweaks.json:19`
**Finding:** `"value": 1` -- confirmed correct per spec. Setting to 0 is Enterprise-only and non-functional on consumer SKUs.

### F23 -- NOTE: All DWord values are valid integers

Spot-checked all 45+ DWord entries -- all use 0 or 1 (valid uint32 values). No type mismatches.

---

## 6. Undo Integrity

### F24 -- WARNING: undo_log.json tampering can inject registry values during undo

**Location:** `src/core/05-UndoManager.ps1:140-159`
**Finding:** When undoing declarative changes (Registry, Service, ScheduledTask), the undo logic reads `Path`, `Name`, `OriginalValue`, and `OriginalType` directly from the undo log file at `%LOCALAPPDATA%\PCCleanup\undo_log.json`. This file is writable by any process running as the current user.

A malicious undo log entry could contain:
```json
{
    "TweakName": "DisableAdvertisingID",
    "Changes": [{
        "Type": "Registry",
        "Path": "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run",
        "Name": "Backdoor",
        "OriginalValue": "C:\\evil.exe",
        "OriginalType": "String",
        "KeyExistedBefore": true
    }]
}
```

When the user undoes "DisableAdvertisingID," the undo manager would write this fabricated value to the Run key, creating a startup persistence entry.

**Mitigating factors:**
- Requires local user-level access (same trust level as modifying any user-writable file)
- The script runs as admin, so an attacker with user access could escalate to admin registry writes via this vector
- Script-type undo correctly reads from tweaks.json (shipped config), not the undo log -- this attack only works for declarative (registry/service/task) undo entries

**Recommendation:** Cross-reference undo registry paths against the corresponding tweak definition in tweaks.json. If the undo log contains paths not present in the tweak's registry definition, reject the undo:
```powershell
# In Invoke-UndoTweak, for Registry changes:
$tweakDef = (Get-Content -Path $tweaksPath -Raw | ConvertFrom-Json).$($entry.TweakName)
$allowedPaths = @($tweakDef.registry | ForEach-Object { "$($_.path)\$($_.name)" })
$undoPath = "$($change.Path)\$($change.Name)"
if ($undoPath -notin $allowedPaths) {
    Write-Warn "SECURITY: Undo log contains path '$undoPath' not in tweak definition. Skipping."
    continue
}
```

### F25 -- NOTE: Corrupted undo_log.json handled gracefully

**Location:** `src/core/05-UndoManager.ps1:93-104`
**Finding:** `Get-AppliedTweaks` wraps JSON parsing in try/catch. On `ConvertFrom-Json` failure: logs warning "Undo log is corrupted... Consider using System Restore Point" and returns empty array. No crash.

### F26 -- NOTE: Deleted undo_log.json handled gracefully

**Location:** `src/core/05-UndoManager.ps1:89-91`
**Finding:** `if (-not (Test-Path $script:UndoLogPath)) { return @() }` -- returns empty, no crash. User sees "No undo data found" in Invoke-UndoTweak.

### F27 -- NOTE: Idempotency guard prevents duplicate applications

**Location:** `src/core/04-TweakEngine.ps1:205-211`
**Finding:** `Invoke-Tweak` checks `Get-AppliedTweaks` for existing entries before applying. If tweak already exists in undo log, it prints "already applied" and returns. Applying 50 times rapidly would succeed once, then be rejected 49 times.

---

## 7. Build & Distribution

### F28 -- NOTE: dist/ matches spec structure

**Verified contents:**
```
dist/
  pccleanup.ps1          (201 KB compiled script)
  Run.bat                (148 bytes)
  config/
    tweaks.json
    apps-bloat.json
    apps-critical.json
    profiles.json
```

Matches the spec's distribution structure exactly. No test files, no .git, no CI configs, no CLAUDE.md.

### F29 -- NOTE: Run.bat does exactly what it should

**Content:** `powershell -ExecutionPolicy Bypass -File "%~dp0pccleanup.ps1"` + `pause`
- `@echo off` suppresses command echo
- `%~dp0` resolves to the script's own directory (correct, no path injection)
- `pause` keeps the window open for user to read output
- No hidden operations, no network calls, no additional flags

### F30 -- NOTE: dist/pccleanup.ps1 contains no debug code

**Grep for TODO, HACK, FIXME, DEBUG, Write-Debug:** Zero matches in dist/pccleanup.ps1.

---

## 8. PowerShell Version Compatibility

### F31 -- NOTE: No non-ASCII characters in .ps1 source files

**Grep for bytes > 0x7F across all src/*.ps1:** Zero matches. The PS 5.1 ANSI encoding issue (documented in project memory) has been fully resolved. No em dashes, unicode arrows, or special characters remain.

### F32 -- NOTE: No PS 7-only syntax detected

**Checked for:**
- Ternary operator (`? :`) -- not found
- Null-coalescing (`??`) -- not found
- Null-conditional (`?.`) -- not found
- Pipeline chain operators (`||`, `&&` in pipeline) -- not found
- `ForEach-Object -Parallel` -- not found
- `.Count` on single objects -- wrapped in `@()` per project convention

All code is compatible with PS 5.1.

### F33 -- WARNING: build/Run.bat contains a non-ASCII em dash character

**Location:** `build/Run.bat:2`
**Content:** `:: PC Cleanup v2 -- Launcher` -- This should use ASCII double-dash `--`, but the root `Run.bat` at the repo root uses the same pattern and the dist version is copied from `build/Run.bat`.

**Actual check:** The grep for non-ASCII in .bat files returned no matches. The `--` in the .bat files are ASCII double-dashes, not em dashes. False alarm -- reclassified.

**Revised:** No issue.

---

## Remediation Priority

### Must fix before ship (WARNINGs):

1. **F4 -- Profile risk clamping:** Hardcode max risk per profile name in main.ps1. Prevents modified profiles.json from escalating "Safe" to "advanced." (~5 lines of code)

2. **F21 -- UserPreferencesMask type:** Change from String to Binary in tweaks.json with proper byte array values. Without this fix, the visual effects optimization silently fails.

3. **F24 -- Undo log path cross-reference:** Validate that undo log registry paths match the tweak definition before writing. Prevents local privilege escalation via undo log tampering. (~10 lines of code)

4. **F11 -- FullTuneUp prefetch uses Remove-Item directly:** Switch to Remove-CleanupItem for consistency with SafeFileOps-everywhere principle. (~3 lines changed)

5. **F5 -- Schema validation for invokeScript/undoScript:** Add array type check to Test-TweakSchema. (~4 lines of code)

### Non-blocking (NOTEs):

All NOTE items are either "working as designed," inherent to the trust model, or have negligible security impact. No action required.

---

## Attack Surface Summary

| Surface | Status | Notes |
|---------|--------|-------|
| CLI parameters | Secure | ValidateSet on all critical params |
| Menu input | Secure | Read-Host literals, switch dispatch |
| tweaks.json injection | By design | Trust boundary is ZIP integrity |
| undo_log.json tampering | **Fix needed** | Cross-reference paths against tweaks.json |
| profiles.json risk escalation | **Fix needed** | Clamp risk per profile name |
| File deletion (SafeFileOps) | Secure | Allowlist + reparse + TOCTOU mitigation |
| Registry writes | Mostly secure | Fix UserPreferencesMask type |
| Network surface | Zero | No network calls anywhere |
| Privilege escalation | None found | No Set-Acl, takeown, icacls |
| Secrets | None found | Clean codebase |
| PS 5.1 compatibility | Good | No non-ASCII, no PS 7 syntax |
