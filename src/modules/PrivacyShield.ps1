# ==============================================================================
# PC Cleanup v2 -- PrivacyShield.ps1
# Privacy/telemetry tweaks from tweaks.json, organized by risk tier.
# Thin UI wrapper -- all tweak definitions live in tweaks.json.
# ==============================================================================

function Show-PrivacyMenu {
    <#
    .SYNOPSIS
        Interactive menu for privacy and telemetry tweaks.
    .DESCRIPTION
        Loads Privacy category tweaks from tweaks.json. Groups by risk
        tier (safe/moderate/advanced). Displays with checkmarks, descriptions,
        and risk-colored indicators. Default selection: all safe-tier tweaks.
        Dispatches to TweakEngine for apply/undo.
    .PARAMETER RiskLevel
        Maximum risk level to display. Default: safe.
    .EXAMPLE
        Show-PrivacyMenu
        Show-PrivacyMenu -RiskLevel moderate
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('safe', 'moderate', 'advanced')]
        [string]$RiskLevel = 'safe'
    )

    $tweaks = Get-Tweaks -Category 'Privacy' -RiskLevel $RiskLevel
    if ($tweaks.Count -eq 0) {
        Write-Info 'No privacy tweaks available for this risk level.'
        return
    }

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

        # Tier header
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
            Write-Info 'All privacy tweaks are already applied.'
            return
        }
        foreach ($item in $unapplied) {
            Invoke-Tweak -Name $item.Id
        }
        return
    }

    if ($choice -eq 'U' -or $choice -eq 'u') {
        $appliedItems = @($displayList | Where-Object { $_.Applied })
        if ($appliedItems.Count -eq 0) {
            Write-Info 'No applied privacy tweaks to undo.'
            return
        }
        foreach ($item in $appliedItems) {
            Invoke-Tweak -Name $item.Id -Undo
        }
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
        foreach ($toggleIndex in $numbers) {
            $toggleItem = $displayList | Where-Object { $_.Index -eq $toggleIndex }
            if ($toggleItem) {
                if ($toggleItem.Applied) {
                    Invoke-Tweak -Name $toggleItem.Id -Undo
                }
                else {
                    Invoke-Tweak -Name $toggleItem.Id
                }
            }
            else {
                Write-Warn "Invalid number: $toggleIndex"
            }
        }
        return
    }

    Write-Warn "Unrecognized input: $choice"
}

function Show-TweakInfo {
    <#
    .SYNOPSIS
        Displays detailed information about a single tweak.
    .DESCRIPTION
        Shows the tweak's full explanation: what it does, why you'd want it,
        what might break, and a link to Microsoft documentation. Also queries
        current system state for registry/service/task entries and shows
        whether the tweak is currently applied via the undo log.
    .PARAMETER Name
        The TweakID to display info for.
    .EXAMPLE
        Show-TweakInfo -Name 'DisableAdvertisingID'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    # Load the tweak directly from JSON (unfiltered by risk/build)
    $tweaksPath = Join-Path $script:ConfigPath 'tweaks.json'
    if (-not (Test-Path $tweaksPath)) {
        Write-Warn "tweaks.json not found."
        return
    }

    $raw = Get-Content -Path $tweaksPath -Raw | ConvertFrom-Json
    $tweak = $raw.$Name

    if ($null -eq $tweak) {
        Write-Warn "Tweak '$Name' not found in tweaks.json."
        return
    }

    # Risk color
    $riskColor = switch ($tweak.risk) {
        'safe'     { 'Green' }
        'moderate' { 'Yellow' }
        'advanced' { 'Red' }
    }

    Write-Host ""
    Write-Host "  $($tweak.name)" -ForegroundColor White
    Write-Host "  $($tweak.description)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Detail: $($tweak.detail)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Risk:   $($tweak.risk)" -ForegroundColor $riskColor
    Write-Host "  Docs:   $($tweak.docsUrl)" -ForegroundColor DarkCyan
    Write-Host ""

    # Current system state for registry entries
    if ($tweak.registry -and $tweak.registry.Count -gt 0) {
        Write-Host "  Registry state:" -ForegroundColor DarkGray
        foreach ($reg in $tweak.registry) {
            $current = Get-PCCleanupRegistryValue -Path $reg.path -Name $reg.name
            $valDisplay = if ($current.Exists) { "$($current.Value) ($($current.Type))" } else { '(not set)' }
            Write-Host "    $($reg.path)\$($reg.name) = $valDisplay" -ForegroundColor DarkGray
        }
    }

    # Current system state for services
    if ($tweak.services -and $tweak.services.Count -gt 0) {
        Write-Host "  Service state:" -ForegroundColor DarkGray
        foreach ($svc in $tweak.services) {
            $current = Get-Service -Name $svc.name -ErrorAction SilentlyContinue
            if ($current) {
                Write-Host "    $($svc.name): $($current.Status) ($($current.StartType))" -ForegroundColor DarkGray
            }
            else {
                Write-Host "    $($svc.name): (not found)" -ForegroundColor DarkGray
            }
        }
    }

    # Applied status from undo log
    $applied = Get-AppliedTweaks
    $entry = @($applied | Where-Object { $_.TweakName -eq $Name })
    if ($entry.Count -gt 0) {
        Write-Host "  Status: APPLIED (at $($entry[0].AppliedAt))" -ForegroundColor Green
    }
    else {
        Write-Host "  Status: Not applied" -ForegroundColor DarkGray
    }
    Write-Host ""
}
