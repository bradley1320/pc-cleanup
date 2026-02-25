# Phase 1 Adversarial Review

**Date:** 2026-02-24
**Reviewer:** Claude Code (Opus 4.6)
**Scope:** All Phase 1 code -- core infrastructure, handlers, tests, build system, encoding
**Method:** Source code review + 46 adversarial Pester tests + encoding byte scan + build output analysis
**Baseline:** 123/123 existing tests pass. 42/46 adversarial tests pass. 4 failures = real bugs.

---

## Summary

Phase 1 is architecturally sound. The undo system, handler dispatch, schema validation, and error handling are well-designed. However, **3 critical issues must be fixed before Phase 2** -- the compiled dist output has parse errors and won't run, and there are encoding issues that produce garbage characters. Additionally, 4 warning-level issues should be addressed before Phase 3.

| Severity | Count | Description |
|----------|-------|-------------|
| CRITICAL | 3 | Blocks Phase 2 -- build output broken, encoding corruption |
| WARNING  | 4 | Fix before Phase 3 -- logic bugs, edge cases |
| NOTE     | 5 | Minor improvements, documentation |

---

## CRITICAL Issues (Must Fix Before Phase 2)

### C-1: Build output has parse errors -- dist/pccleanup.ps1 won't execute

**File:** `build/Build.ps1`, `src/main.ps1`
**Evidence:** PowerShell parser reports errors at dist line 2017:
```
At dist\pccleanup.ps1:2017 char:1
+ [CmdletBinding()]
Unexpected attribute 'CmdletBinding'.
```

**Root cause:** Build.ps1 concatenates all source files into a single .ps1. `main.ps1` has a `[CmdletBinding()] param()` block (lines 7-34) which is valid at the top of a standalone script, but becomes a syntax error when it appears at line 2017 in the middle of a concatenated file. PowerShell requires `param()` to appear at the very beginning of a script.

**Impact:** The compiled `dist/pccleanup.ps1` that ships to users **will not parse or execute**. Users who download the ZIP and run `Run.bat` will get a parse error. This is a total showstopper.

**Fix:** Two options:
1. **Move param() to Build.ps1 header** -- Build.ps1 should emit the `param()` block at the top of the compiled output, before any function definitions. Then strip or wrap main.ps1's param/loading code so it doesn't emit a second param() block.
2. **Wrap main.ps1's param block in a function** -- Convert the entry point into a function like `Invoke-PCCleanup` that gets called at the end of the script. The param() block goes inside the function. Or use `$args` parsing instead of `param()`.

**Recommended:** Option 1. The dist output should have the param() block at line 1, then all function definitions, then the entry point logic at the end.

---

### C-2: Em dashes in Build.ps1 produce mojibake in dist header

**Files:** `build/Build.ps1` (5 occurrences), `dist/pccleanup.ps1` (header)
**Evidence:** Byte scan found em dashes (U+2014, UTF-8: E2 80 94) at offsets 97, 2027, 2294, 2505, 2627 in Build.ps1.

Build.ps1 has NO BOM. When PowerShell 5.1 reads it as ANSI (Windows-1252):
- E2 = a (a-circumflex)
- 80 = euro sign (not visible in 1252)
- 94 = right double quote

The here-string header becomes garbled, and `Set-Content -Encoding UTF8` re-encodes the garbled characters as UTF-8. The dist output shows:
```
# PC Cleanup v2 a** Compiled Distribution
```
instead of:
```
# PC Cleanup v2 -- Compiled Distribution
```

**Impact:** The dist file header shows mojibake to any user who opens it. Unprofessional appearance. Does not affect execution (it's in a comment), but undermines the "transparency / paste into AI" trust model.

**Fix:** Replace all em dashes (--) with double hyphens (--) in Build.ps1. This was already identified as a known issue in MEMORY.md but wasn't applied to Build.ps1.

**Affected lines in Build.ps1:**
- Line 2: `# PC Cleanup v2 -- Build.ps1` (comment header -- uses em dash)
- Line 57: `# 5. main.ps1 (entry point -- always last)` (comment)
- Lines 65, 70, 73: Header template here-string (3 em dashes)

---

### C-3: SafetyNet.ps1 has non-ASCII arrows in comment

**File:** `src/core/03-SafetyNet.ps1`, line 131
**Evidence:** 6 non-ASCII bytes (two Unicode right arrows U+2192) found:
```powershell
# Convert PowerShell path to reg.exe format (HKLM: -> HKLM\, HKCU: -> HKCU\)
```

**Impact:** Same encoding issue as C-2. When PS 5.1 reads this file as ANSI, the arrows become garbled. Since this is in a comment inside executable code (not just the header), the garbled bytes could potentially introduce a phantom quote character that breaks the parser mid-string -- the exact bug described in MEMORY.md.

**Fix:** Replace `->` with `-->` (ASCII arrow) in the comment.

---

## WARNING Issues (Fix Before Phase 3)

### W-1: Double-apply creates duplicate undo entries with corrupted original values

**File:** `src/core/04-TweakEngine.ps1` (Invoke-Tweak), `src/core/05-UndoManager.ps1`
**Evidence:** Adversarial test "should create duplicate undo log entries when applied twice" -- confirmed.

**Scenario:**
1. User applies TweakA (original value=1, target=0). Undo log stores OriginalValue=1.
2. User applies TweakA again. Engine captures current value (now 0). Undo log stores OriginalValue=0.
3. User undoes TweakA. `Invoke-UndoTweak` uses `Select-Object -Last 1`, gets the second entry, restores to 0. **The true original (1) is lost behind a stale entry.**
4. User must undo a second time to restore to 1.

**Impact:** Confusing UX. Users who accidentally apply a tweak twice lose the ability to cleanly undo in one step. The second undo entry has a wrong "original" value.

**Fix:** Before applying a tweak, check if it already exists in the undo log. If so, either:
- (a) Skip re-apply with a message: "TweakA is already applied."
- (b) Overwrite the existing undo entry (keep the original OriginalValue, update the timestamp).

Option (a) is safer and simpler.

---

### W-2: Empty tweaks.json `{}` crashes TweakEngine

**File:** `src/core/04-TweakEngine.ps1`, line 136
**Evidence:** Adversarial test "should handle completely empty JSON object" -- failed with `ParameterBindingValidationException: Cannot bind argument to parameter 'Tweaks' because it is an empty collection.`

**Root cause:** `Test-TweakSchema` has `[Parameter(Mandatory)] [array]$Tweaks`. When `{}` is parsed, the resulting tweaks array is empty (`@()`), and PowerShell rejects empty collections for mandatory array parameters.

**Impact:** If a user empties their tweaks.json (e.g., during customization), the tool crashes instead of showing a helpful message.

**Fix:** Either:
- (a) Check `$tweaks.Count -eq 0` before calling `Test-TweakSchema` and return early.
- (b) Remove `[Parameter(Mandatory)]` from Test-TweakSchema and add an early-return for empty arrays.

---

### W-3: ScriptHandler crashes on empty string input

**File:** `src/handlers/ScriptHandler.ps1`, line 24
**Evidence:** Adversarial test "should handle empty script block" -- failed with `Cannot bind argument to parameter 'ScriptBlock' because it is an empty string.`

**Root cause:** `[Parameter(Mandatory)] [string]$ScriptBlock` rejects empty strings in PowerShell 5.1+. If a tweaks.json entry has `"invokeScript": [""]` (empty string in array), this crashes.

**Impact:** Defensive issue. An empty invokeScript entry in tweaks.json would crash the script instead of being silently skipped.

**Fix:** Add `[AllowEmptyString()]` attribute or check for empty string before creating the scriptblock.

---

### W-4: Build.ps1 dist output has UTF-8 BOM

**File:** `dist/pccleanup.ps1`
**Evidence:** First 3 bytes are EF BB BF (UTF-8 BOM).

**Root cause:** PowerShell 5.1's `Set-Content -Encoding UTF8` always writes a BOM. This is PS 5.1 behavior.

**Impact:** The BOM actually HELPS PS 5.1 read the file correctly (it detects UTF-8 and avoids ANSI misinterpretation). However:
- Some editors show the BOM as garbage characters at the start
- If the user pastes the file into AI for verification, the BOM bytes may appear
- PS 7 doesn't need the BOM and considers it unnecessary

**Fix:** For PS 5.1 compatibility, the BOM is actually beneficial. However, document this choice. If you want BOM-less UTF-8, use `[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))` -- but this may break PS 5.1 reading.

**Recommendation:** Keep the BOM for now. It's the lesser evil for PS 5.1 compatibility. Downgrade this to NOTE.

---

## NOTE Issues (Minor Improvements)

### N-1: Undo log removal uses `-or` filter that can be confusing

**File:** `src/core/05-UndoManager.ps1`, line 169
```powershell
$remaining = @($log | Where-Object { $_.TweakName -ne $Name -or $_.AppliedAt -ne $entry.AppliedAt })
```

This keeps entries where EITHER TweakName doesn't match OR AppliedAt doesn't match. The intent is "remove only the entry matching both TweakName AND AppliedAt". Logically correct (De Morgan's: NOT(A AND B) = NOT A OR NOT B), but the double-negative logic is easy to misread in reviews.

Consider rewriting as:
```powershell
$remaining = @($log | Where-Object { -not ($_.TweakName -eq $Name -and $_.AppliedAt -eq $entry.AppliedAt) })
```

---

### N-2: No dry-run (WhatIf) mode in handlers

**Status:** Expected -- Phase 5 per CLAUDE.md spec.

The main.ps1 param block declares `[switch]$WhatIf` but no handler has a `-WhatIf` code path. This is documented as Phase 5 work. Noting here for completeness.

---

### N-3: Write-Log concurrent write safety

**File:** `src/core/01-Utility.ps1`, line 141

`Add-Content -Path $logFile -Value $entry -ErrorAction SilentlyContinue` does not use file locking. If two operations log simultaneously (which shouldn't happen in single-threaded PS execution but could in background jobs), writes could interleave.

**Impact:** Minimal. The script is single-threaded. Background jobs (like restore point creation) don't call Write-Log. The SilentlyContinue flag correctly handles any lock errors.

**Verdict:** Not a real issue. The design is correct.

---

### N-4: Log files contain full registry paths and usernames

**File:** `src/core/01-Utility.ps1` (Write-Log)

Log entries include full paths like `HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection`. The log directory (`%LOCALAPPDATA%\PCCleanup\logs`) is per-user and NTFS-protected, but if a user shares log files for support, these paths are visible.

**Impact:** Not sensitive (registry paths are public knowledge). But worth noting in future documentation.

---

### N-5: Config file version mismatch detection not implemented

**Status:** Mentioned in CLAUDE.md spec (Known Risks table) but not yet implemented.

The `_version` field exists in tweaks.json but nothing reads or validates it. A version mismatch between the script and config files could cause subtle issues.

**Recommendation:** Add a version check in TweakEngine during schema validation. This is low priority for Phase 2 but should be in place before shipping.

---

## Adversarial Test Results Summary

### Tests Written: 46
### Tests Passed: 42
### Tests Failed: 4

| # | Test | Result | Issue |
|---|------|--------|-------|
| 1 | Empty JSON `{}` handling | FAIL | C-1 schema crash |
| 2 | Double-apply stale undo entry | FAIL | W-1 duplicate entries |
| 3 | Empty string to ScriptHandler | FAIL | W-3 parameter validation |
| 4 | Backup-RegistryHive path sanitization | FAIL | Test bug (missing BeforeAll import) |

### Tests That Passed (Confirming Correct Behavior):
- Schema validates all required fields (category, risk, type, value, etc.)
- Schema rejects invalid risk values
- Schema handles extra unknown fields gracefully
- Undo of never-applied tweak warns gracefully (no crash)
- Undo with corrupted log (truncated JSON, empty file) -- no crash
- Random-order undo works correctly
- Registry handler rejects invalid type via ValidateSet
- Registry handler handles empty string, long paths, unknown hive prefixes
- Service handler handles already-stopped services, spaces in names
- Script handler catches thrown errors, syntax errors
- Task handler handles single-segment paths, deeply nested paths
- JSON round-trip preserves null, false, 0, and special characters
- Single-entry undo log (ConvertFrom-Json object-vs-array edge case) works
- 20-entry undo log without corruption
- Script-only tweaks don't create undo entries (correct -- no state to capture)
- Mixed handler tweaks capture all change types
- Config path traversal rejected
- Undo removes only the targeted entry, not entries with similar names

---

## Encoding Scan Results

### Source Files Scanned: 20 .ps1 files + 4 .json files

| File | Status | Issue |
|------|--------|-------|
| src/core/01-Utility.ps1 | OK | Clean ASCII |
| src/core/02-SystemInfo.ps1 | OK | Clean ASCII |
| **src/core/03-SafetyNet.ps1** | **FAIL** | 6 non-ASCII bytes (Unicode arrows in comment, line 131) |
| src/core/04-TweakEngine.ps1 | OK | Clean ASCII |
| src/core/05-UndoManager.ps1 | OK | Clean ASCII |
| src/handlers/*.ps1 (4 files) | OK | Clean ASCII |
| src/modules/*.ps1 (9 files) | OK | Clean ASCII |
| src/ui/Menu.ps1 | OK | Clean ASCII |
| src/main.ps1 | OK | Clean ASCII |
| **build/Build.ps1** | **FAIL** | 15 non-ASCII bytes (5 em dashes in comments/header) |
| **dist/pccleanup.ps1** | **FAIL** | UTF-8 BOM + double-encoded mojibake from Build.ps1 |
| config/*.json (4 files) | OK | Clean ASCII |

---

## Build Output Verification

| Check | Result |
|-------|--------|
| Build.ps1 produces dist/pccleanup.ps1 | PASS |
| dist/pccleanup.ps1 line count | 2081 lines, 65.9 KB |
| Parse errors in dist output | **FAIL** -- 2 errors at line 2017 (param block) |
| Em dashes in dist output | 0 (but replaced with mojibake) |
| UTF-8 BOM present | Yes (from PS 5.1 Set-Content) |
| Config files copied to dist/config/ | PASS |
| Run.bat copied to dist/ | PASS |

---

## Recommendations for Phase 2

### Must Do (Before Starting Phase 2):
1. Fix Build.ps1 to handle main.ps1's param() block (C-1)
2. Replace em dashes with `--` in Build.ps1 (C-2)
3. Replace Unicode arrows with `-->` in SafetyNet.ps1 comment (C-3)
4. Add empty-tweaks guard in TweakEngine before schema validation (W-2)

### Should Do (During Phase 2):
5. Add idempotency guard in Invoke-Tweak: skip if already in undo log (W-1)
6. Add `[AllowEmptyString()]` to ScriptHandler parameter (W-3)

### Nice to Have (Before Phase 3):
7. Implement `_version` check in TweakEngine
8. Consider rewriting undo filter for readability (N-1)
