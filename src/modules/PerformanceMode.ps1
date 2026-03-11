# ==============================================================================
# PC Cleanup v2 -- PerformanceMode.ps1
# Performance optimizations: power plan, visual effects, gaming tweaks.
# Thin UI wrapper around TweakEngine for "Performance" category tweaks.
# ==============================================================================

# Tweak IDs that modify visual/shell-cached settings and need an Explorer refresh
$script:VisualTweakIds = @(
    'OptimizeVisualEffects'
    'DisableTransparency'
    'DisableStartupDelay'
)

function Show-PerformanceMenu {
    <#
    .SYNOPSIS
        Interactive menu for performance optimizations.
    .DESCRIPTION
        Loads Performance category tweaks from tweaks.json, groups by risk
        tier, displays with descriptions. Detects laptop vs desktop for
        battery warnings, detects SSD vs HDD for relevant tweaks.
        After applying visual tweaks, broadcasts WM_SETTINGCHANGE or
        offers to restart explorer.exe so changes are visible immediately.
    .PARAMETER RiskLevel
        Maximum risk level to display. Default: safe.
    .EXAMPLE
        Show-PerformanceMenu
        Show-PerformanceMenu -RiskLevel moderate
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('safe', 'moderate', 'advanced')]
        [string]$RiskLevel = 'safe'
    )

    $tweaks = Get-Tweaks -Category 'Performance' -RiskLevel $RiskLevel
    if ($tweaks.Count -eq 0) {
        Write-Info 'No performance tweaks available for this risk level.'
        return
    }

    # System detection warnings
    Show-SystemWarnings

    $applied = Get-AppliedTweaks

    # Group by risk tier
    $tiers = [ordered]@{
        'safe'     = @($tweaks | Where-Object { $_.risk -eq 'safe' })
        'moderate' = @($tweaks | Where-Object { $_.risk -eq 'moderate' })
        'advanced' = @($tweaks | Where-Object { $_.risk -eq 'advanced' })
    }

    # Build numbered display list
    $displayList = @()
    $index = 1

    foreach ($tier in $tiers.GetEnumerator()) {
        if ($tier.Value.Count -eq 0) { continue }

        $tierColor = switch ($tier.Key) {
            'safe'     { 'Green' }
            'moderate' { 'Yellow' }
            'advanced' { 'Red' }
        }
        Write-Host ""
        Write-Host "  === $($tier.Key.ToUpper()) TIER ===" -ForegroundColor $tierColor

        foreach ($tweak in $tier.Value) {
            $isApplied = @($applied | Where-Object { $_.TweakName -eq $tweak.Id }).Count -gt 0
            $status = if ($isApplied) { '[X]' } else { '[ ]' }
            Write-Host "  $status $index. $($tweak.name) -- $($tweak.description)" -ForegroundColor $tierColor
            $displayList += [PSCustomObject]@{
                Index   = $index
                Id      = $tweak.Id
                Name    = $tweak.name
                Applied = $isApplied
            }
            $index++
        }
    }

    Write-Host ""
    Write-Host "  [A] Apply all unapplied  [U] Undo all applied  [I #] Info  [B] Back"
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
        $unapplied = @($displayList | Where-Object { -not $_.Applied })
        if ($unapplied.Count -eq 0) {
            Write-Info 'All performance tweaks are already applied.'
            return
        }
        $appliedVisual = $false
        foreach ($item in $unapplied) {
            Invoke-Tweak -Name $item.Id
            if ($item.Id -in $script:VisualTweakIds) { $appliedVisual = $true }
        }
        if ($appliedVisual) { Invoke-ExplorerRefresh }
        return
    }

    if ($choice -eq 'U' -or $choice -eq 'u') {
        $appliedItems = @($displayList | Where-Object { $_.Applied })
        if ($appliedItems.Count -eq 0) {
            Write-Info 'No applied performance tweaks to undo.'
            return
        }
        $undoVisual = $false
        foreach ($item in $appliedItems) {
            Invoke-Tweak -Name $item.Id -Undo
            if ($item.Id -in $script:VisualTweakIds) { $undoVisual = $true }
        }
        if ($undoVisual) { Invoke-ExplorerRefresh }
        return
    }

    # Info command: I followed by number
    if ($choice -match '^[Ii]\s*(\d+)$') {
        $infoIndex = [int]$Matches[1]
        $infoItem = $displayList | Where-Object { $_.Index -eq $infoIndex }
        if ($infoItem) {
            Show-TweakInfo -Name $infoItem.Id
        }
        else {
            Write-Warn "Invalid number: $infoIndex"
        }
        return
    }

    # Toggle by number (supports comma/space-separated: 1,2,3 or 1 2 3 or 1, 2, 3)
    if ($choice -match '^\d+([,\s]+\d+)*$') {
        $numbers = $choice -split '[,\s]+' | Where-Object { $_ -ne '' } | ForEach-Object { [int]$_ }
        $appliedVisual = $false
        foreach ($toggleIndex in $numbers) {
            $toggleItem = $displayList | Where-Object { $_.Index -eq $toggleIndex }
            if ($toggleItem) {
                if ($toggleItem.Applied) {
                    Invoke-Tweak -Name $toggleItem.Id -Undo
                }
                else {
                    Invoke-Tweak -Name $toggleItem.Id
                }
                if ($toggleItem.Id -in $script:VisualTweakIds) { $appliedVisual = $true }
            }
            else {
                Write-Warn "Invalid number: $toggleIndex"
            }
        }
        if ($appliedVisual) { Invoke-ExplorerRefresh }
        return
    }

    Write-Warn "Unrecognized input: $choice"
}

# --- Internal helper functions ---

function Show-SystemWarnings {
    <#
    .SYNOPSIS
        Displays system-specific warnings before performance tweaks.
    .DESCRIPTION
        Detects laptop vs desktop (battery warning for power plan changes)
        and SSD vs HDD (informational note about disk-related tweaks).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Displays multiple warnings')]
    [CmdletBinding()]
    param()

    $chassis = Get-ChassisType
    if ($chassis -eq 'Laptop') {
        Write-Warn 'Laptop detected -- power plan changes will significantly reduce battery life.'
        Write-Warn 'Consider switching back to Balanced when on battery.'
    }

    try {
        $isSSD = Test-IsSSD -DriveLetter 'C'
        if (-not $isSSD) {
            Write-Info 'HDD detected on system drive -- some performance improvements may be more noticeable.'
        }
    }
    catch {
        # Can't detect drive type -- skip warning silently
        $null = $_
    }
}

function Invoke-ExplorerRefresh {
    <#
    .SYNOPSIS
        Broadcasts WM_SETTINGCHANGE to refresh the Windows shell after visual tweaks.
    .DESCRIPTION
        After applying visual tweaks (transparency, animations, context menus),
        the Windows shell caches old values in memory. Changes are not visible
        until the shell re-reads the registry. This function broadcasts
        WM_SETTINGCHANGE via P/Invoke. If P/Invoke fails, offers to restart
        explorer.exe as a fallback.
    #>
    [CmdletBinding()]
    param()

    Write-Info 'Refreshing Windows shell to apply visual changes...'

    # Try P/Invoke WM_SETTINGCHANGE broadcast
    $refreshed = Send-SettingChange
    if ($refreshed) {
        Write-Success 'Shell refreshed -- visual changes should be visible now.'
        return
    }

    # P/Invoke failed -- offer Explorer restart as fallback
    Write-Warn 'Could not broadcast shell refresh. Restarting Explorer will apply visual changes.'
    if (Get-UserConfirmation -Prompt 'Restart Explorer now? (taskbar will briefly disappear)' -Default 'Y') {
        try {
            Stop-Process -Name explorer -Force -ErrorAction Stop
            Start-Process explorer.exe
            Write-Success 'Explorer restarted -- visual changes applied.'
        }
        catch {
            Write-Warn "Could not restart Explorer: $($_.Exception.Message)"
            Write-Info 'Visual changes will take effect after you log out and back in.'
        }
    }
    else {
        Write-Info 'Visual changes will take effect after you log out and back in, or restart Explorer manually.'
    }
}

function Send-SettingChange {
    <#
    .SYNOPSIS
        Broadcasts WM_SETTINGCHANGE via Win32 SendMessageTimeout.
    .DESCRIPTION
        Uses Add-Type to define the P/Invoke signature and calls
        SendMessageTimeoutW with HWND_BROADCAST and WM_SETTINGCHANGE.
        Returns $true on success, $false on failure.
    .OUTPUTS
        [bool] Whether the broadcast succeeded.
    #>
    [CmdletBinding()]
    param()

    try {
        # Only add the type once per session
        if (-not ([System.Management.Automation.PSTypeName]'PCCleanup.NativeMethods').Type) {
            Add-Type -Namespace 'PCCleanup' -Name 'NativeMethods' -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeoutW(
    IntPtr hWnd,
    uint Msg,
    UIntPtr wParam,
    string lParam,
    uint fuFlags,
    uint uTimeout,
    out UIntPtr lpdwResult);
'@
        }

        $HWND_BROADCAST   = [IntPtr]0xFFFF
        $WM_SETTINGCHANGE = [uint32]0x001A
        $SMTO_ABORTIFHUNG = [uint32]0x0002
        $timeout           = [uint32]5000
        $result            = [UIntPtr]::Zero

        $ret = [PCCleanup.NativeMethods]::SendMessageTimeoutW(
            $HWND_BROADCAST,
            $WM_SETTINGCHANGE,
            [UIntPtr]::Zero,
            'Environment',
            $SMTO_ABORTIFHUNG,
            $timeout,
            [ref]$result
        )

        return $ret -ne [IntPtr]::Zero
    }
    catch {
        Write-Log "PerformanceMode: WM_SETTINGCHANGE P/Invoke failed: $($_.Exception.Message)"
        return $false
    }
}
