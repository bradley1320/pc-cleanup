# Phase 2 Security Audit: QuickClean / Disk Cleanup Module

**Date:** 2026-02-24
**Scope:** QuickClean.ps1 module design, file deletion safety, privilege model
**Auditors:**
- Council (Gemini, Grok, DeepSeek) -- design review via council-mcp
- Claude Opus 4.6 -- independent security audit with CVE research
- Claude Code (separate terminal) -- adversarial code review + 46 attack tests

**Verdict: 5 hard blockers must be resolved before implementing QuickClean.**

---

## Executive Summary

The QuickClean module runs as Administrator and recursively deletes files from user-writable directories (`%TEMP%`, browser caches). This is the single most dangerous operation in the entire tool -- not because of what it does, but because of what an attacker can trick it into doing.

All 5 auditors (3 council + 2 independent) reached the same conclusion: **the module as currently specified is vulnerable to junction-based arbitrary file deletion attacks** identical to CVE-2025-21420 (Windows Disk Cleanup EoP). A standard user can create NTFS junctions in `%TEMP%` without special privileges, redirecting the elevated cleanup tool to delete system files.

The existing safety infrastructure (System Restore Points, registry backups, undo_log.json) provides **zero protection for file deletion** -- it was designed for registry/service/task operations only.

---

## Consensus Findings (All Auditors Agree)

### HB-1: Junction/Reparse Point Attacks -- CRITICAL

**Risk:** CRITICAL | **Unanimity:** 5/5 auditors flagged this

A standard user can create NTFS directory junctions (`mklink /J`) without `SeCreateSymbolicLinkPrivilege`. If the elevated cleanup tool recursively deletes contents of `%TEMP%\target` without checking for reparse points, and `%TEMP%\target` is a junction pointing to `C:\Windows\System32`, the tool follows the junction and deletes system files with full Administrator privileges.

**CVE Precedent:**
- CVE-2025-21420 -- Windows Disk Cleanup (cleanmgr.exe) EoP via junction
- CVE-2025-67905 -- Malwarebytes AdwCleaner EoP via symlink
- CVE-2024-52535 -- Dell SupportAssist symlink attack
- Microsoft MSRC: 32 of 42 path redirection CVEs in 2024 used attacker-created junctions

**Attack scenario:**
```
Attacker (standard user):
  1. mkdir %TEMP%\cache_folder && create .tmp files (passes scan)
  2. Wait for elevated pccleanup.ps1 to scan %TEMP%
  3. rmdir %TEMP%\cache_folder
  4. mklink /J %TEMP%\cache_folder C:\Windows\System32\drivers
  5. Elevated tool deletes "temp files" --> actually deletes system drivers
```

**Required mitigation:**
```powershell
# Check ReparsePoint attribute on EVERY directory before recursing
function Remove-SafeDirectory {
    param([string]$Path, [switch]$WhatIf)

    $dirInfo = [System.IO.DirectoryInfo]::new($Path)
    if (-not $dirInfo.Exists) { return }

    # CRITICAL: refuse to operate on reparse points
    if ($dirInfo.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
        Write-Warn "Skipping reparse point (junction/symlink): $Path"
        Write-Log "SECURITY: Refused to recurse into reparse point: $Path"
        return
    }

    foreach ($entry in $dirInfo.EnumerateFileSystemInfos()) {
        if ($entry.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
            Write-Log "SECURITY: Skipped reparse point: $($entry.FullName)"
            continue
        }
        if ($entry -is [System.IO.DirectoryInfo]) {
            Remove-SafeDirectory -Path $entry.FullName -WhatIf:$WhatIf
        } else {
            if ($WhatIf) {
                Write-Info "WhatIf: Would delete $($entry.FullName)"
            } else {
                try { $entry.Delete() }
                catch { Write-Log "Could not delete: $($entry.FullName) - $($_.Exception.Message)" }
            }
        }
    }
}
```

**Design rule:** `Remove-Item -Recurse` must NEVER be used on user-writable directories. PowerShell follows junctions/symlinks during recursive deletion (confirmed: GitHub issues #621, #16664, #19714).

---

### HB-2: PowerShell -WhatIf Destroys Junctions -- CRITICAL

**Risk:** CRITICAL | **Unanimity:** 4/5 auditors flagged this (Claude independent + all 3 council)

PowerShell has a confirmed, unfixed bug: `Remove-Item -WhatIf` on junctions and symbolic links **actually deletes the reparse point** instead of simulating. This affects both PS 5.1 and PS 7.x.

**References:** PowerShell GitHub issues [#16664](https://github.com/PowerShell/PowerShell/issues/16664), [#19714](https://github.com/PowerShell/PowerShell/issues/19714)

**Required mitigation:** The `-WhatIf` code path must be a completely separate branch that performs ONLY read operations. Never delegate to PowerShell's native `-WhatIf` for file operations.

```powershell
function Remove-CleanupItem {
    param([string]$Path, [switch]$WhatIf)

    # Application-level WhatIf -- NEVER delegates to cmdlet -WhatIf
    if ($WhatIf) {
        Write-Info "WhatIf: Would delete $Path"
        return  # Return immediately, no destructive API calls
    }
    # ... actual deletion logic ...
}
```

---

### HB-3: Path Allowlist Enforcement Missing -- HIGH

**Risk:** HIGH | **Unanimity:** 5/5

No mechanism restricts which paths the tool can operate on. A bug in browser detection, a malformed config, or a future code change could accidentally target user documents.

**Required mitigation:**
```powershell
$script:AllowedCleanupRoots = @(
    [System.IO.Path]::GetFullPath($env:TEMP),
    [System.IO.Path]::GetFullPath("$env:SystemRoot\Temp"),
    [System.IO.Path]::GetFullPath("$env:SystemRoot\Prefetch"),
    [System.IO.Path]::GetFullPath("$env:SystemRoot\SoftwareDistribution\Download")
    # + dynamically validated browser cache paths
)

function Test-PathWithinAllowlist {
    param([string]$Path)
    $resolved = [System.IO.Path]::GetFullPath($Path)
    foreach ($root in $script:AllowedCleanupRoots) {
        if ($resolved.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}
```

Every file deletion must pass this check. Defense-in-depth: even if the reparse point check fails due to a race condition, the allowlist prevents operations on system directories.

---

### HB-4: No Safety Net for File Deletion -- HIGH

**Risk:** HIGH | **Unanimity:** 5/5

The undo system covers registry/service/task changes. File deletion is permanent with no recovery mechanism.

**Required mitigations (all auditors converge on these):**
1. **Pre-deletion manifest** -- JSON log of all files targeted for deletion, saved to `%LOCALAPPDATA%\PCCleanup\logs\cleanup_manifest_[timestamp].json` (Gemini, Claude)
2. **Anomaly detection** -- if actual bytes deleted exceeds scan estimate by >20%, log warning (Claude)
3. **VSS verification** -- check that at least one Volume Shadow Copy exists; if not, warn prominently (Claude)
4. **Threshold confirmation** -- if total exceeds 10GB or 100K files, require explicit confirmation (Claude, Grok)

**Split decision on quarantine:**
- Grok recommended moving files to a quarantine directory instead of deleting
- Gemini and Claude noted this defeats the purpose for temp file cleanup (doubles disk usage)
- DeepSeek proposed offering "Move to Recycle Bin" vs "Permanent Delete" for certain targets
- **Resolution:** Pre-deletion manifest is mandatory. Quarantine is optional UX enhancement for non-temp targets.

---

### HB-5: TOCTOU Race Condition -- HIGH

**Risk:** HIGH | **Unanimity:** 4/5 (Gemini, Grok, DeepSeek, Claude independent)

Time gap between scan (preview) and delete (execution) allows filesystem to change. An attacker or background process can replace a directory with a junction after the scan verified it.

**Required mitigations:**
1. Re-validate every path at deletion time (not relying on scan-time state)
2. Check reparse point attribute immediately before each delete operation
3. Use canonical path resolution `[System.IO.Path]::GetFullPath()` and verify against allowlist at delete time
4. Display actual deletion count after cleanup (not scan estimate)

---

## Additional Findings

### F-6: AppData Junction Loops -- MEDIUM

**Flagged by:** Claude independent, Gemini

Windows ships with built-in junctions for backward compatibility (`Application Data` -> `AppData\Local`, etc.). `Get-ChildItem -Recurse` on `%LOCALAPPDATA%` follows these, creating infinite loops. Running as Administrator with `-Force` bypasses the DENY ACE that normally prevents this.

**Mitigation:** Resolved by HB-1's reparse point check. Also maintain a blocklist of known Windows junction names as defense-in-depth.

---

### F-7: OneDrive Cloud Placeholders -- MEDIUM

**Flagged by:** All 5 auditors

Files with `FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS` (0x00400000) are OneDrive placeholders. Deleting them:
- Triggers cloud sync deletion across all devices
- Reports inaccurate "space recovered" (zero local bytes)
- May trigger mass downloads if scan reads file contents

**Mitigation:**
```powershell
function Test-IsCloudPlaceholder {
    param([System.IO.FileSystemInfo]$Item)
    $recallOnDataAccess = [System.IO.FileAttributes]0x00400000
    $recallOnOpen       = [System.IO.FileAttributes]0x00040000
    return ($Item.Attributes.HasFlag($recallOnDataAccess) -or $Item.Attributes.HasFlag($recallOnOpen))
}
```

Detect OneDrive sync roots via registry. Skip cloud placeholders during scan and cleanup.

---

### F-8: Long Paths (>260 chars) -- MEDIUM

**Flagged by:** All 5 auditors

PS 5.1 inherits MAX_PATH (260 chars). `%TEMP%` paths are already long; nested caches exceed this. `Get-ChildItem` and `Remove-Item` throw `PathTooLongException`.

**Mitigation:** Use `\\?\` prefix for .NET API calls. Catch `PathTooLongException` explicitly and display user-friendly message. For scan accuracy, use `[System.IO.Directory]::EnumerateFiles()` with `\\?\` prefix.

---

### F-9: Prefetch/WU Cache Service Interaction -- MEDIUM

**Flagged by:** Claude independent, DeepSeek

- Prefetch deletion while Prefetch service is running can degrade performance
- SoftwareDistribution deletion during active Windows Update can corrupt in-progress updates

**Mitigation:** Stop `wuauserv` before cleaning WU cache; restart after. Document that Prefetch regenerates automatically after cleaning.

---

### F-10: Locked File Handling -- LOW

**Flagged by:** All 5 auditors

The spec says "Skips locked files silently" -- correct behavior. Implementation should distinguish `IOException` (locked -- expected) from `UnauthorizedAccessException` (permissions -- may indicate a problem).

---

## Auditor-Specific Unique Insights

### Gemini (Council)
- **"Kill List" strategy for browsers**: Instead of just warning, offer to close browser processes before cache cleanup
- **No wildcard deletion in root**: Never run `Remove-Item C:\Windows\Temp\*` -- iterate children individually
- **Pre-Cleanup Manifest**: JSON manifest of all files flagged for deletion as audit trail

### Grok (Council)
- **Quarantine Instead of Delete**: Move files to quarantine directory for recovery option
- **Minimize privilege scope**: Run scanning under user context, elevate only for deletion
- **Penetration testing**: Simulate attacks with custom scripts before shipping

### DeepSeek (Council)
- **Secure token system**: Validate paths as user, pass validated path list to elevated process via secure temp file
- **Phased implementation**: Security foundation first (reparse + validation), then cleanup features
- **`FILE_FLAG_OPEN_REPARSE_POINT`**: Use Win32 API flag to prevent following symlinks at the kernel level
- **`MoveFileEx` with `MOVEFILE_DELAY_UNTIL_REBOOT`**: Option for locked files that must be cleaned

### Claude Independent Audit
- **CVE research**: Identified specific CVE numbers and Microsoft MSRC RedirectionGuard documentation
- **PS Remove-Item -WhatIf bug**: Specific GitHub issue references (#16664, #19714) proving -WhatIf is destructive on reparse points
- **Recommended new core module**: `SafeFileOps.ps1` between SafetyNet and TweakEngine for shared file safety infrastructure

---

## Disagreements and Resolutions

| Topic | Positions | Resolution |
|-------|-----------|------------|
| Quarantine vs permanent delete | Grok: quarantine all; Gemini/Claude: impractical for temp files | Pre-deletion manifest mandatory; quarantine optional for non-temp targets |
| Privilege separation (scan as user, delete as admin) | Grok/DeepSeek: separate contexts; Gemini/Claude: adds complexity for marginal benefit since tool already runs elevated | Path allowlist + reparse check provides equivalent protection; privilege separation deferred to future work |
| Win32 API vs PowerShell .NET | DeepSeek: use CreateFile with FILE_FLAG_OPEN_REPARSE_POINT; others: .NET sufficient | .NET `EnumerateFileSystemInfos()` + attribute check is sufficient for PS 5.1; Win32 P/Invoke adds complexity |

---

## Hard Blockers Summary

| # | Finding | Severity | Requirement |
|---|---------|----------|-------------|
| HB-1 | Junction/reparse point check missing | CRITICAL | Every recursive scan/delete must check `[System.IO.FileAttributes]::ReparsePoint` on every directory entry. No exceptions. |
| HB-2 | `Remove-Item -WhatIf` destroys junctions | CRITICAL | WhatIf code path must be completely separate, performing ONLY read operations. Never delegate to PS native `-WhatIf`. |
| HB-3 | Path allowlist enforcement missing | HIGH | Every deletion must validate resolved path falls within explicit allowed roots. |
| HB-4 | No safety net for file deletion | HIGH | Pre-deletion manifest mandatory. Anomaly detection mandatory. VSS check recommended. |
| HB-5 | TOCTOU race between scan and delete | HIGH | Re-validate paths and reparse attributes at deletion time, not just scan time. |

---

## Recommended Architecture

Based on all 5 auditors' convergent recommendations, QuickClean requires a new safety foundation:

### New core module: `src/core/03.5-SafeFileOps.ps1`

Loaded between SafetyNet (03) and TweakEngine (04). Provides:

1. **`Remove-SafeDirectory`** -- reparse-point-aware recursive deletion using .NET `EnumerateFileSystemInfos()`
2. **`Test-PathWithinAllowlist`** -- validates resolved path against hardcoded allowed roots
3. **`Test-IsReparsePoint`** -- checks `[System.IO.FileAttributes]::ReparsePoint`
4. **`Test-IsCloudPlaceholder`** -- detects OneDrive Files On Demand placeholders
5. **`New-CleanupManifest`** -- generates pre-deletion JSON manifest
6. **`Get-SafePath`** -- applies `\\?\` prefix for long path support

This module is reusable by any future module that touches the filesystem (DiskAnalysis, duplicate file finder, etc.).

### Project-wide rules
- **Ban `Remove-Item -Recurse`** on user-writable directories
- **Ban delegating to PS `-WhatIf`** for file operations
- **Mandatory allowlist check** before every file deletion

---

## Phase 1 Adversarial Review Integration

The separate adversarial review (docs/audits/phase1-adversarial-review.md) found 3 CRITICALs and 4 WARNINGs in the Phase 1 infrastructure code. **All have been fixed:**

| Issue | Status | Fix Applied |
|-------|--------|-------------|
| C-1: dist/pccleanup.ps1 parse error (param block at line 2017) | FIXED | Build.ps1 now extracts main.ps1's param block and emits it at line 14 of dist output |
| C-2: Em dashes in Build.ps1 produce mojibake | FIXED | All em dashes replaced with `--` |
| C-3: Unicode arrows in SafetyNet.ps1 | FIXED | Replaced with `-->` |
| W-1: Double-apply creates duplicate undo entries | FIXED | Idempotency guard: skip if tweak already in undo log |
| W-2: Empty tweaks.json crashes TweakEngine | FIXED | Guard `$tweaks.Count -gt 0` before schema validation |
| W-3: ScriptHandler crashes on empty string | FIXED | Added `[AllowEmptyString()]` + early return |
| W-4: UTF-8 BOM in dist output | KEPT | BOM is beneficial for PS 5.1 compatibility |

**Verification:** 169/169 tests pass (123 original + 46 adversarial). Build output parses cleanly. Zero non-ASCII bytes in source files.

---

## Recommendation

Phase 1 infrastructure is now solid (all adversarial bugs fixed, 169 tests green). Phase 2 implementation should proceed with the following order:

1. **Implement `SafeFileOps.ps1`** -- the security foundation for all file operations
2. **Write Pester tests for SafeFileOps** -- including junction attack simulation, reparse point detection, allowlist enforcement
3. **Implement QuickClean.ps1** -- using SafeFileOps exclusively for all file operations
4. **Expand tweaks.json** -- privacy/telemetry catalog
5. **Implement PrivacyShield.ps1** -- UI wrapper around TweakEngine

The SafeFileOps module is the gating dependency. No file deletion code should be written until the reparse point guard and path allowlist are in place and tested.

---

## Sources

- [CVE-2025-21420: Windows Disk Cleanup EoP](https://gbhackers.com/poc-exploit-windows-disk-cleanup/)
- [CVE-2025-67905: Malwarebytes AdwCleaner Symlink Attack](https://www.thehackerwire.com/malwarebytes-adwcleaner-privilege-escalation-via-symlink/)
- [CVE-2024-52535: Dell SupportAssist Symlink Vulnerability](https://www.cve.news/cve-2024-52535/)
- [Microsoft MSRC: RedirectionGuard](https://www.microsoft.com/en-us/msrc/blog/2025/06/redirectionguard-mitigating-unsafe-junction-traversal-in-windows)
- [Palo Alto Unit42: Windows Redirection Trust Mitigation](https://unit42.paloaltonetworks.com/junctions-windows-redirection-trust-mitigation/)
- [Mandiant/Google: Why Arbitrary File Deletion Vulnerabilities Matter](https://cloud.google.com/blog/topics/threat-intelligence/arbitrary-file-deletion-vulnerabilities/)
- [CyberArk: Follow the Link -- Exploiting Symbolic Links](https://www.cyberark.com/resources/threat-research-blog/follow-the-link-exploiting-symbolic-links-with-ease)
- [PowerShell #19714: Remove-Item -WhatIf on Junctions Actually Deletes](https://github.com/PowerShell/PowerShell/issues/19714)
- [PowerShell #16664: Remove-Item Removes Symbolic Links with -WhatIf](https://github.com/PowerShell/PowerShell/issues/16664)
- [PowerShell #621: Fix Remove-Item on Symbolic Link to Directory](https://github.com/powershell/powershell/issues/621)
- [CWE-367: TOCTOU Race Condition](https://cwe.mitre.org/data/definitions/367.html)
- [Microsoft: Create Symbolic Links Policy](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/create-symbolic-links)
