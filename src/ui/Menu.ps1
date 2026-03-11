# ==============================================================================
# PC Cleanup v2 -- Menu.ps1
# Terminal UI: banner, main menu, sub-menus, selection interface.
# ==============================================================================

function Show-Banner {
    <#
    .SYNOPSIS
        Displays the PC Cleanup v2 banner and version info.
    #>
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "  ====================================================" -ForegroundColor DarkCyan
    Write-Host "              PC Cleanup v2.0                          " -ForegroundColor White
    Write-Host "     Windows Optimization Toolkit                      " -ForegroundColor DarkGray
    Write-Host "  ====================================================" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Open source | Every change is reversible" -ForegroundColor DarkGray
    Write-Host ""

    if (-not (Test-IsAdmin)) {
        Write-Warn 'Not running as Administrator -- some features will be limited.'
        Write-Info 'Right-click Run.bat and select "Run as Administrator" for full access.'
        Write-Host ""
    }
}

function Show-MainMenu {
    <#
    .SYNOPSIS
        Displays the main menu and returns the user's selection.
    .DESCRIPTION
        Presents numbered options for each module. Returns a string
        identifying the selected action, or $null to exit.
    .OUTPUTS
        [string] The selected menu option identifier, or $null.
    #>
    [CmdletBinding()]
    param()

    Write-Host "  --- Main Menu ---" -ForegroundColor White
    Write-Host ""
    Write-Host "  1.  Quick Clean          - Remove temp files and browser caches"
    Write-Host "  2.  Startup Manager      - Manage startup programs"
    Write-Host "  3.  Performance Mode     - Optimize visual effects and power plan"
    Write-Host "  4.  Privacy Shield       - Disable telemetry and tracking"
    Write-Host "  5.  Network Reset        - Troubleshoot network issues"
    Write-Host "  6.  Disk Analysis        - View disk usage and folder sizes"
    Write-Host "  7.  Security Check       - Check security health (read-only)"
    Write-Host "  8.  System Report        - Before/after metrics comparison"
    Write-Host ""
    Write-Host "  9.  Full Tune-Up         - Run all safe optimizations" -ForegroundColor Green
    Write-Host "  10. Backup & Restore     - View/undo applied changes"
    Write-Host ""
    Write-Host "  Q.  Quit"
    Write-Host ""

    try {
        $choice = Read-Host '  Choice'
    }
    catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($choice)) { return $null }
    $choice = $choice.Trim()

    switch ($choice) {
        '1'  { return 'QuickClean' }
        '2'  { return 'Startup' }
        '3'  { return 'Performance' }
        '4'  { return 'Privacy' }
        '5'  { return 'Network' }
        '6'  { return 'Disk' }
        '7'  { return 'Security' }
        '8'  { return 'Report' }
        '9'  { return 'TuneUp' }
        '10' { return 'BackupRestore' }
        { $_ -eq 'Q' -or $_ -eq 'q' } { return $null }
        default {
            Write-Warn "Unrecognized input: $choice"
            return 'Invalid'
        }
    }
}

function Show-BackupRestoreMenu {
    <#
    .SYNOPSIS
        Interactive menu for viewing and undoing applied tweaks.
    .DESCRIPTION
        Lists all applied tweaks from undo_log.json with metadata.
        Supports per-tweak undo and undo-all. Uses UndoManager.
    #>
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host "       BACKUP & RESTORE          " -ForegroundColor White
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host ""

    # Show safety net status
    $safety = Get-SafetyStatus
    Write-Host "  Safety Nets:" -ForegroundColor White
    Write-Host "    System Restore Points: $($safety.RestorePoints)"
    Write-Host "    Registry Backups:      $($safety.Backups)"
    Write-Host "    Applied Tweaks:        $($safety.UndoLogEntries)"
    Write-Host ""

    $applied = Get-AppliedTweaks
    if ($applied.Count -eq 0) {
        Write-Info 'No applied tweaks to restore.'
        Write-Host ""
        return
    }

    # Build numbered list
    Write-Host "  Applied Tweaks:" -ForegroundColor White
    Write-Host ""

    $displayList = @()
    $index = 1
    foreach ($entry in $applied) {
        $appliedDate = try { ([datetime]$entry.AppliedAt).ToString('yyyy-MM-dd HH:mm') } catch { $entry.AppliedAt }
        $changeCount = if ($entry.Changes) { @($entry.Changes).Count } else { 0 }
        Write-Host "  $index. $($entry.TweakName)" -ForegroundColor White -NoNewline
        Write-Host "  ($($entry.Category), $changeCount change(s), applied $appliedDate)" -ForegroundColor DarkGray

        $displayList += [PSCustomObject]@{
            Index = $index
            Name  = $entry.TweakName
        }
        $index++
    }

    Write-Host ""
    Write-Host "  [#]  Undo specific tweak     [A] Undo all     [B] Back"
    Write-Host ""

    try {
        $choice = Read-Host '  Choice'
    }
    catch {
        return
    }

    if ([string]::IsNullOrWhiteSpace($choice)) { return }
    $choice = $choice.Trim()

    if ($choice -eq 'B' -or $choice -eq 'b') { return }

    if ($choice -eq 'A' -or $choice -eq 'a') {
        if (Get-UserConfirmation -Prompt "Undo all $($applied.Count) applied tweak(s)?" -Default 'N') {
            Invoke-UndoAll
        }
        else {
            Write-Skip 'Undo all cancelled.'
        }
        return
    }

    if ($choice -match '^\d+$') {
        $undoIndex = [int]$choice
        $undoItem = $displayList | Where-Object { $_.Index -eq $undoIndex }
        if ($undoItem) {
            Invoke-UndoTweak -Name $undoItem.Name
        }
        else {
            Write-Warn "Invalid number: $undoIndex"
        }
        return
    }

    Write-Warn "Unrecognized input: $choice"
}

function Show-SelectionMenu {
    <#
    .SYNOPSIS
        Displays a checkbox-style selection menu for multi-select operations.
    .DESCRIPTION
        Used by modules that let users pick from a list (cleanup targets,
        startup programs, tweaks). Supports select/deselect all.
    .PARAMETER Title
        The menu title.
    .PARAMETER Items
        Array of items to display, each with Name, Description, and Selected properties.
    .OUTPUTS
        [array] The selected items.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [array]$Items
    )

    Write-Host ""
    Write-Host "  $Title" -ForegroundColor White
    Write-Host ""

    $index = 1
    foreach ($item in $Items) {
        $check = if ($item.Selected) { '[X]' } else { '[ ]' }
        $desc = if ($item.Description) { " -- $($item.Description)" } else { '' }
        Write-Host "  $check $index. $($item.Name)$desc"
        $index++
    }

    Write-Host ""
    Write-Host "  [#] Toggle  [A] Select all  [N] Select none  [D] Done  [B] Back"
    Write-Host ""

    try {
        $choice = Read-Host '  Choice'
    }
    catch {
        return @($Items | Where-Object { $_.Selected })
    }

    if ([string]::IsNullOrWhiteSpace($choice)) {
        return @($Items | Where-Object { $_.Selected })
    }

    $choice = $choice.Trim()

    if ($choice -eq 'B' -or $choice -eq 'b') { return @() }

    if ($choice -eq 'D' -or $choice -eq 'd') {
        return @($Items | Where-Object { $_.Selected })
    }

    if ($choice -eq 'A' -or $choice -eq 'a') {
        foreach ($item in $Items) { $item.Selected = $true }
        return @($Items)
    }

    if ($choice -eq 'N' -or $choice -eq 'n') {
        foreach ($item in $Items) { $item.Selected = $false }
        return @()
    }

    if ($choice -match '^\d+([,\s]+\d+)*$') {
        $numbers = $choice -split '[,\s]+' | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ }
        foreach ($toggleIndex in $numbers) {
            if ($toggleIndex -ge 1 -and $toggleIndex -le $Items.Count) {
                $Items[$toggleIndex - 1].Selected = -not $Items[$toggleIndex - 1].Selected
            }
        }
        return @($Items | Where-Object { $_.Selected })
    }

    return @($Items | Where-Object { $_.Selected })
}

function Invoke-MenuLoop {
    <#
    .SYNOPSIS
        Runs the interactive menu loop until the user quits.
    .DESCRIPTION
        Displays banner, then loops through Show-MainMenu, dispatching to
        the appropriate module for each selection. Handles all navigation.
    .PARAMETER RiskLevel
        Maximum risk level for tweak operations. Default: safe.
    .PARAMETER WhatIf
        Pass-through for WhatIf mode across all modules.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'WhatIf passed to sub-functions')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'Application-level WhatIf')]
    [CmdletBinding()]
    param(
        [ValidateSet('safe', 'moderate', 'advanced')]
        [string]$RiskLevel = 'safe',

        [switch]$WhatIf
    )

    Show-Banner

    if ($WhatIf) {
        Write-Info 'Running in WhatIf (preview) mode -- no changes will be made.'
        Write-Host ""
    }

    while ($true) {
        $selection = Show-MainMenu

        if ($null -eq $selection) {
            Write-Host ""
            Write-Info 'Goodbye!'
            Write-Host ""
            return
        }

        if ($selection -eq 'Invalid') { continue }

        switch ($selection) {
            'QuickClean' {
                $targets = Get-CleanupTargets -ShowProgress
                if ($targets.Count -gt 0) {
                    # Build selection items
                    $selItems = @()
                    foreach ($target in $targets) {
                        $countText = if ($target.Estimated) { "$($target.FileCount)+" } else { "$($target.FileCount)" }
                        $sizeText = if ($target.Estimated) { "~$(Format-FileSize $target.Size)" } else { "$(Format-FileSize $target.Size)" }
                        $desc = "$countText files, $sizeText"
                        if ($target.Estimated) { $desc += ' (estimated)' }
                        if ($target.Hint) { $desc = "$($target.Hint) -- $desc" }
                        $selItems += [PSCustomObject]@{
                            Name        = $target.Name
                            Description = $desc
                            Selected    = $false
                            Target      = $target
                        }
                    }
                    $selected = Show-SelectionMenu -Title 'Select cleanup targets:' -Items $selItems
                    if ($selected.Count -gt 0) {
                        $selectedTargets = @($selected | ForEach-Object { $_.Target })
                        Invoke-Cleanup -Targets $selectedTargets -WhatIf:$WhatIf
                    }
                    else {
                        Write-Info 'No targets selected.'
                    }
                }
                else {
                    Write-Info 'No cleanup targets found.'
                }
            }
            'Startup' {
                Show-StartupMenu
            }
            'Performance' {
                Show-PerformanceMenu -RiskLevel $RiskLevel
            }
            'Privacy' {
                Show-PrivacyMenu -RiskLevel $RiskLevel
            }
            'Network' {
                Show-NetworkResetMenu -WhatIf:$WhatIf
            }
            'Disk' {
                Show-DiskAnalysisMenu
            }
            'Security' {
                Get-SecurityReport | Out-Null
            }
            'Report' {
                Show-ReportMenu
            }
            'TuneUp' {
                Invoke-FullTuneUp -WhatIf:$WhatIf
            }
            'BackupRestore' {
                Show-BackupRestoreMenu
            }
        }

        Write-Host ""
        Pause-Script
        Write-Host ""
    }
}

function Show-ReportMenu {
    <#
    .SYNOPSIS
        Sub-menu for system report and snapshot operations.
    #>
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host "        SYSTEM REPORT            " -ForegroundColor White
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host ""
    Write-Host '  1. Take "Before" Snapshot'
    Write-Host '  2. Take "After" Snapshot'
    Write-Host "  3. Compare Snapshots"
    Write-Host "  4. View Current Metrics"
    Write-Host ""
    Write-Host "  [B] Back"
    Write-Host ""

    try {
        $choice = Read-Host '  Choice'
    }
    catch {
        return
    }

    if ([string]::IsNullOrWhiteSpace($choice)) { return }
    $choice = $choice.Trim()

    if ($choice -eq 'B' -or $choice -eq 'b') { return }

    switch ($choice) {
        '1' { Save-SystemSnapshot -Label 'Before' }
        '2' { Save-SystemSnapshot -Label 'After' }
        '3' { Compare-Snapshots }
        '4' {
            $snapshot = Get-SystemSnapshot
            Write-Host ""
            Write-Host "  Current System Metrics:" -ForegroundColor White
            Write-Host "    Boot time:      $($snapshot.BootTimeMs)ms (source: $($snapshot.BootTimeSource))"
            Write-Host "    Processes:      $($snapshot.ProcessCount)"
            Write-Host "    Free disk:      $(Format-FileSize $snapshot.FreeDiskBytes)"
            Write-Host "    Startup items:  $($snapshot.StartupCount)"
            Write-Host ""
        }
        default {
            Write-Warn "Unrecognized input: $choice"
        }
    }
}

function Show-StartupMenu {
    <#
    .SYNOPSIS
        Interactive menu for startup program management.
    .DESCRIPTION
        Lists startup programs with metadata, allows enable/disable.
    #>
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host "       STARTUP MANAGER           " -ForegroundColor White
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host ""

    Write-Info 'Scanning startup programs...'
    $programs = Get-StartupPrograms

    if ($programs.Count -eq 0) {
        Write-Info 'No startup programs found.'
        return
    }

    $displayList = @()
    $index = 1

    foreach ($prog in $programs) {
        $riskColor = switch ($prog.Risk) {
            'critical' { 'Red' }
            'bloat'    { 'Yellow' }
            default    { 'White' }
        }

        $orphanTag = if ($prog.IsOrphaned) { ' (file missing)' } else { '' }
        $riskTag = switch ($prog.Risk) {
            'critical' { ' [DO NOT DISABLE]' }
            'bloat'    { ' [bloatware]' }
            default    { '' }
        }

        $publisher = if ($prog.Publisher) { " ($($prog.Publisher))" } else { '' }

        Write-Host "  $index. $($prog.Name)$publisher$riskTag$orphanTag" -ForegroundColor $riskColor
        if ($prog.Description) {
            Write-Host "     $($prog.Description)" -ForegroundColor DarkGray
        }

        $displayList += [PSCustomObject]@{
            Index   = $index
            Name    = $prog.Name
            Program = $prog
        }
        $index++
    }

    Write-Host ""
    Write-Host "  [#] Disable  [E #] Enable  [B] Back"
    Write-Host ""

    try {
        $choice = Read-Host '  Choice'
    }
    catch {
        return
    }

    if ([string]::IsNullOrWhiteSpace($choice)) { return }
    $choice = $choice.Trim()

    if ($choice -eq 'B' -or $choice -eq 'b') { return }

    # Enable command: E followed by number
    if ($choice -match '^[Ee]\s*(\d+)$') {
        $enableIndex = [int]$Matches[1]
        $enableItem = $displayList | Where-Object { $_.Index -eq $enableIndex }
        if ($enableItem) {
            Enable-StartupProgram -Name $enableItem.Name
        }
        else {
            Write-Warn "Invalid number: $enableIndex"
        }
        return
    }

    # Disable by number (supports comma/space-separated: 1,2,3 or 1 2 3 or 1, 2, 3)
    if ($choice -match '^\d+([,\s]+\d+)*$') {
        $numbers = $choice -split '[,\s]+' | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ }
        foreach ($disableIndex in $numbers) {
            $disableItem = $displayList | Where-Object { $_.Index -eq $disableIndex }
            if ($disableItem) {
                if ($disableItem.Program.Risk -eq 'critical') {
                    Write-Warn "WARNING: $($disableItem.Name) is marked as critical."
                    if ($disableItem.Program.RiskReason) {
                        Write-Warn "Reason: $($disableItem.Program.RiskReason)"
                    }
                    if (-not (Get-UserConfirmation -Prompt "Disable critical program '$($disableItem.Name)' anyway?" -Default 'N')) {
                        Write-Skip "Skipped $($disableItem.Name)."
                        continue
                    }
                }
                Disable-StartupProgram -Name $disableItem.Name
            }
            else {
                Write-Warn "Invalid number: $disableIndex"
            }
        }
        return
    }

    Write-Warn "Unrecognized input: $choice"
}
