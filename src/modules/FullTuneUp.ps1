# ==============================================================================
# PC Cleanup v2 -- FullTuneUp.ps1
# Orchestrates safe-tier cleanup + performance + privacy in one flow.
# Only applies safe-tier tweaks. Does NOT include Network Reset.
# ==============================================================================

function Invoke-FullTuneUp {
    <#
    .SYNOPSIS
        Runs the complete safe-tier optimization pipeline.
    .DESCRIPTION
        Orchestration flow:
        1. Create System Restore Point
        2. Create registry backup
        3. Take "before" snapshot
        4. Run QuickClean (all targets, auto mode)
        5. Apply Performance tweaks (safe tier)
        6. Apply Privacy tweaks (safe tier)
        7. Apply Prefetch cleanup (admin only)
        8. Run DISM component cleanup (admin only, with warning + separate confirmation)
        9. Display summary
        10. Prompt to take "after" snapshot (after restart)
    .PARAMETER WhatIf
        Preview mode -- show what would happen without making changes.
    .EXAMPLE
        Invoke-FullTuneUp
        Invoke-FullTuneUp -WhatIf
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'WhatIf used in conditional branches')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'Application-level WhatIf -- not using ShouldProcess')]
    [CmdletBinding()]
    param(
        [switch]$WhatIf
    )

    Write-Host ""
    Write-Host "  ==============================" -ForegroundColor DarkCyan
    Write-Host "       FULL TUNE-UP (Safe)       " -ForegroundColor DarkCyan
    Write-Host "  ==============================" -ForegroundColor DarkCyan
    Write-Host ""

    if ($WhatIf) {
        Write-Info 'WhatIf mode -- previewing changes without applying.'
        Write-Host ""
    }

    # Show what will happen and require confirmation before proceeding
    Write-Host "  Full Tune-Up will:" -ForegroundColor White
    Write-Host "    - Clean temp files and caches"
    Write-Host "    - Apply safe-tier performance tweaks"
    Write-Host "    - Apply safe-tier privacy tweaks"
    Write-Host "    - Clean Prefetch files (admin only)"
    Write-Host "    - Run DISM component cleanup (optional, admin only)"
    Write-Host ""
    Write-Host "  A System Restore Point will be created first." -ForegroundColor Gray
    Write-Host ""

    if (-not $WhatIf) {
        if (-not (Get-UserConfirmation -Prompt 'Proceed with Full Tune-Up?' -Default 'Y')) {
            Write-Skip 'Full Tune-Up cancelled.'
            return
        }
        Write-Host ""
    }

    $summary = [PSCustomObject]@{
        RestorePoint      = $false
        RegistryBackup    = $false
        SnapshotTaken     = $false
        CleanupFiles      = 0
        CleanupBytes      = [long]0
        PerformanceTweaks = 0
        PrivacyTweaks     = 0
        PrefetchCleaned   = $false
        DismRun           = $false
    }

    # --- Step 1: System Restore Point ---
    Write-Info 'Step 1/8: Creating safety backup...'
    if ($WhatIf) {
        Write-Info 'WhatIf: Would create System Restore Point.'
    }
    else {
        $summary.RestorePoint = New-SafetyRestorePoint
    }

    # --- Step 2: Registry backup ---
    if ($WhatIf) {
        Write-Info 'WhatIf: Would export registry backup.'
    }
    else {
        $backupDir = Join-Path $env:LOCALAPPDATA 'PCCleanup\backups'
        $backupResult = Backup-RegistryHive -Path 'HKLM:\SOFTWARE\Policies' -OutputDir $backupDir
        $summary.RegistryBackup = $null -ne $backupResult
    }

    # --- Step 3: Take "before" snapshot ---
    Write-Info 'Step 2/8: Taking "before" snapshot...'
    if ($WhatIf) {
        Write-Info 'WhatIf: Would capture system snapshot.'
    }
    else {
        try {
            Save-SystemSnapshot -Label 'Before' | Out-Null
            $summary.SnapshotTaken = $true
        }
        catch {
            Write-Warn "Could not take snapshot: $($_.Exception.Message)"
        }
    }

    # --- Step 4: QuickClean (all targets, auto mode) ---
    Write-Info 'Step 3/8: Running Quick Clean...'
    if ($WhatIf) {
        $targets = @(Get-CleanupTargets)
        foreach ($target in $targets) {
            Write-Info "WhatIf: Would clean $($target.Name) ($($target.FileCount) files, $(Format-FileSize $target.Size))"
        }
        $summary.CleanupFiles = ($targets | Measure-Object -Property FileCount -Sum).Sum
        $summary.CleanupBytes = ($targets | Measure-Object -Property Size -Sum).Sum
    }
    else {
        $targets = @(Get-CleanupTargets)
        if ($targets.Count -gt 0) {
            $cleanResult = Invoke-Cleanup -Targets $targets
            $summary.CleanupFiles = $cleanResult.TotalFiles
            $summary.CleanupBytes = $cleanResult.TotalBytes
        }
    }

    # --- Step 5: Performance tweaks (safe tier) ---
    Write-Info 'Step 4/8: Applying safe performance tweaks...'
    $perfTweaks = @(Get-Tweaks -Category 'Performance' -RiskLevel 'safe')
    if ($perfTweaks.Count -gt 0) {
        if ($WhatIf) {
            foreach ($tweak in $perfTweaks) {
                Write-Info "WhatIf: Would apply '$($tweak.name)'"
            }
        }
        else {
            foreach ($tweak in $perfTweaks) {
                Invoke-Tweak -Name $tweak.Id
            }
        }
        $summary.PerformanceTweaks = $perfTweaks.Count
    }
    else {
        Write-Info 'No performance tweaks available for safe tier.'
    }

    # --- Step 6: Privacy tweaks (safe tier) ---
    Write-Info 'Step 5/8: Applying safe privacy tweaks...'
    $privacyTweaks = @(Get-Tweaks -Category 'Privacy' -RiskLevel 'safe')
    if ($privacyTweaks.Count -gt 0) {
        if ($WhatIf) {
            foreach ($tweak in $privacyTweaks) {
                Write-Info "WhatIf: Would apply '$($tweak.name)'"
            }
        }
        else {
            foreach ($tweak in $privacyTweaks) {
                Invoke-Tweak -Name $tweak.Id
            }
        }
        $summary.PrivacyTweaks = $privacyTweaks.Count
    }
    else {
        Write-Info 'No privacy tweaks available for safe tier.'
    }

    # --- Step 7: Prefetch cleanup (admin only) ---
    Write-Info 'Step 6/8: Prefetch cleanup...'
    if (Test-IsAdmin) {
        $prefetchPath = Join-Path $env:SystemRoot 'Prefetch'
        if (Test-Path $prefetchPath) {
            if ($WhatIf) {
                Write-Info 'WhatIf: Would clean Prefetch directory.'
            }
            else {
                try {
                    $prefetchFiles = Get-ChildItem -Path $prefetchPath -File -ErrorAction SilentlyContinue
                    $count = 0
                    foreach ($file in $prefetchFiles) {
                        $removeResult = Remove-CleanupItem -Path $file.FullName
                        $count += $removeResult.DeletedFiles
                    }
                    Write-Success "Cleaned $count prefetch files."
                    $summary.PrefetchCleaned = $true
                }
                catch {
                    Write-Warn "Could not clean Prefetch: $($_.Exception.Message)"
                }
            }
        }
        else {
            Write-Skip 'Prefetch directory not found.'
        }
    }
    else {
        Write-Skip 'Prefetch cleanup requires administrator privileges.'
    }

    # --- Step 8: DISM component cleanup (admin only, separate confirmation) ---
    Write-Info 'Step 7/8: DISM component cleanup...'
    if (Test-IsAdmin) {
        Write-Host ""
        Write-Warn 'DISM component cleanup permanently removes superseded update packages.'
        Write-Warn 'You will not be able to uninstall updates that shipped before this point.'
        Write-Warn 'This may take 5-15 minutes and requires a reboot.'
        Write-Host ""

        if ($WhatIf) {
            Write-Info 'WhatIf: Would run DISM /Online /Cleanup-Image /StartComponentCleanup.'
        }
        else {
            $dismConfirm = Get-UserConfirmation -Prompt 'Run DISM component cleanup?' -Default 'N'
            if ($dismConfirm) {
                Write-Info 'Running DISM component cleanup (this may take several minutes)...'
                try {
                    $dismResult = & dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
                    $dismExit = $LASTEXITCODE
                    if ($dismExit -eq 0) {
                        Write-Success 'DISM component cleanup completed.'
                        $summary.DismRun = $true
                    }
                    else {
                        Write-Warn "DISM exited with code $dismExit. Some cleanup may not have completed."
                        Write-Log "DISM output: $($dismResult -join '; ')"
                    }
                }
                catch {
                    Write-Err -Message 'DISM component cleanup failed' -Cause $_.Exception.Message -Fix 'Try running DISM manually from an elevated command prompt.'
                }
            }
            else {
                Write-Skip 'DISM component cleanup skipped by user.'
            }
        }
    }
    else {
        Write-Skip 'DISM component cleanup requires administrator privileges.'
    }

    # --- Step 9: Display summary ---
    Write-Host ""
    Write-Host "  ==============================" -ForegroundColor Green
    Write-Host "         TUNE-UP SUMMARY        " -ForegroundColor Green
    Write-Host "  ==============================" -ForegroundColor Green
    Write-Host ""

    if ($WhatIf) {
        Write-Host "  Mode:              WhatIf (preview only)" -ForegroundColor Yellow
    }
    Write-Host "  Restore Point:     $(if ($summary.RestorePoint) { 'Created' } else { 'Skipped' })"
    Write-Host "  Registry Backup:   $(if ($summary.RegistryBackup) { 'Saved' } else { 'Skipped' })"
    Write-Host "  Files Cleaned:     $($summary.CleanupFiles) ($(Format-FileSize $summary.CleanupBytes))"
    Write-Host "  Performance Tweaks: $($summary.PerformanceTweaks) applied"
    Write-Host "  Privacy Tweaks:    $($summary.PrivacyTweaks) applied"
    Write-Host "  Prefetch:          $(if ($summary.PrefetchCleaned) { 'Cleaned' } else { 'Skipped' })"
    Write-Host "  DISM Cleanup:      $(if ($summary.DismRun) { 'Completed' } else { 'Skipped' })"
    Write-Host ""

    # --- Step 10: Prompt for "after" snapshot ---
    if (-not $WhatIf) {
        Write-Info 'For accurate before/after comparison, restart your PC and then run:'
        Write-Info '  .\pccleanup.ps1 -Snapshot After'
        Write-Info '  .\pccleanup.ps1 -Snapshot Compare'
        Write-Host ""
        Write-Info 'Tip: First reboot after changes may be slower. Restart twice for accurate boot time.'
    }

    return $summary
}
