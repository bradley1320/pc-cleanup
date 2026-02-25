# ==============================================================================
# PC Cleanup v2 -- main.ps1
# Entry point: parameter parsing, module loading, UI launch.
# Built with Claude Code (Anthropic). Open source and fully auditable.
# ==============================================================================

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Params consumed in CLI dispatch logic below')]
[CmdletBinding()]
param(
    # Apply a preset profile (Safe, Gaming, Privacy, Custom)
    [ValidateSet('Safe', 'Gaming', 'Privacy', 'Custom')]
    [string]$ProfileName,

    # Run a specific module directly
    [ValidateSet('QuickClean', 'Startup', 'Performance', 'Privacy',
                 'Network', 'Disk', 'Security', 'Report', 'TuneUp')]
    [string]$Module,

    # Maximum risk level for tweak operations
    [ValidateSet('safe', 'moderate', 'advanced')]
    [string]$Risk = 'safe',

    # Dry-run mode: preview changes without applying
    [switch]$WhatIf,

    # Undo a specific tweak or 'All' to undo everything
    [string]$Undo,

    # Generate system report
    [switch]$Report,

    # Take or compare system snapshots
    [ValidateSet('Before', 'After', 'Compare')]
    [string]$Snapshot
)

# --- Module Loading ---
# Load order is critical: core (01-06) -> handlers -> modules -> ui
# All paths resolved via $PSScriptRoot -- never relative to working directory

$corePath     = Join-Path $PSScriptRoot 'core'
$handlerPath  = Join-Path $PSScriptRoot 'handlers'
$modulePath   = Join-Path $PSScriptRoot 'modules'
$uiPath       = Join-Path $PSScriptRoot 'ui'

# Core infrastructure (numerical order matters)
Get-ChildItem -Path $corePath -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
    . $_.FullName
}

# Handlers
Get-ChildItem -Path $handlerPath -Filter '*.ps1' | ForEach-Object {
    . $_.FullName
}

# Feature modules
Get-ChildItem -Path $modulePath -Filter '*.ps1' | ForEach-Object {
    . $_.FullName
}

# UI
Get-ChildItem -Path $uiPath -Filter '*.ps1' | ForEach-Object {
    . $_.FullName
}

# --- CLI Dispatch ---

# Undo mode: -Undo All or -Undo "TweakName"
if ($Undo) {
    if ($Undo -eq 'All') {
        Invoke-UndoAll
    }
    else {
        Invoke-UndoTweak -Name $Undo
    }
    return
}

# Snapshot mode: -Snapshot Before/After/Compare
if ($Snapshot) {
    switch ($Snapshot) {
        'Before'  { Save-SystemSnapshot -Label 'Before' }
        'After'   { Save-SystemSnapshot -Label 'After' }
        'Compare' { Compare-Snapshots }
    }
    return
}

# Report mode: -Report
if ($Report) {
    Get-SecurityReport | Out-Null
    Write-Host ""
    $snap = Get-SystemSnapshot
    Write-Host "  Current System Metrics:" -ForegroundColor White
    Write-Host "    Boot time:      $($snap.BootTimeMs)ms (source: $($snap.BootTimeSource))"
    Write-Host "    Processes:      $($snap.ProcessCount)"
    Write-Host "    Free disk:      $(Format-FileSize $snap.FreeDiskBytes)"
    Write-Host "    Startup items:  $($snap.StartupCount)"
    Write-Host ""
    return
}

# Profile mode: -Profile Safe/Gaming/Privacy/Custom
if ($ProfileName) {
    if ($ProfileName -eq 'Custom') {
        Invoke-MenuLoop -RiskLevel 'advanced' -WhatIf:$WhatIf
        return
    }

    $profilesPath = Join-Path (Join-Path $PSScriptRoot '..') 'config' | Join-Path -ChildPath 'profiles.json'
    if (-not (Test-Path $profilesPath)) {
        $profilesPath = Join-Path $script:ConfigPath 'profiles.json'
    }
    if (-not (Test-Path $profilesPath)) {
        Write-Err -Message "profiles.json not found" -Cause "Config file missing" -Fix "Restore from original ZIP."
        return
    }

    $profiles = Get-Content -Path $profilesPath -Raw | ConvertFrom-Json
    $selectedProfile = $profiles.$ProfileName
    if ($null -eq $selectedProfile) {
        Write-Err -Message "Profile '$ProfileName' not found in profiles.json" -Cause "Invalid profile name" -Fix "Available profiles: Safe, Gaming, Privacy, Custom."
        return
    }

    Show-Banner
    Write-Info "Applying profile: $ProfileName -- $($selectedProfile.description)"
    Write-Host ""

    $profileRisk = $selectedProfile.risk
    $profileModules = @($selectedProfile.modules)
    $profileCategories = @($selectedProfile.includeCategories)

    if ($WhatIf) {
        Write-Info 'WhatIf mode -- previewing changes without applying.'
        Write-Host ""
    }

    # Run QuickClean if in module list
    if ('QuickClean' -in $profileModules) {
        Write-Info 'Running Quick Clean...'
        if ($WhatIf) {
            $targets = Get-CleanupTargets
            foreach ($target in $targets) {
                Write-Info "WhatIf: Would clean $($target.Name) ($(Format-FileSize $target.Size))"
            }
        }
        else {
            $targets = Get-CleanupTargets
            if ($targets.Count -gt 0) {
                Invoke-Cleanup -Targets $targets
            }
        }
    }

    # Apply tweak categories
    foreach ($cat in $profileCategories) {
        Write-Info "Applying $cat tweaks ($profileRisk tier)..."
        $catTweaks = Get-Tweaks -Category $cat -RiskLevel $profileRisk
        foreach ($tweak in $catTweaks) {
            if ($WhatIf) {
                Write-Info "WhatIf: Would apply '$($tweak.name)'"
            }
            else {
                Invoke-Tweak -Name $tweak.Id
            }
        }
    }

    Write-Host ""
    Write-Success "Profile '$ProfileName' applied."
    return
}

# Module mode: -Module <name>
if ($Module) {
    Show-Banner
    switch ($Module) {
        'QuickClean' {
            $targets = Get-CleanupTargets
            if ($targets.Count -gt 0) {
                if ($WhatIf) {
                    Invoke-Cleanup -Targets $targets -WhatIf
                }
                else {
                    Invoke-Cleanup -Targets $targets
                }
            }
            else {
                Write-Info 'No cleanup targets found.'
            }
        }
        'Startup'     { Show-StartupMenu }
        'Performance' { Show-PerformanceMenu -RiskLevel $Risk }
        'Privacy'     { Show-PrivacyMenu -RiskLevel $Risk }
        'Network'     { Show-NetworkResetMenu -WhatIf:$WhatIf }
        'Disk'        { Show-DiskAnalysisMenu }
        'Security'    { Get-SecurityReport | Out-Null }
        'Report'      { Show-ReportMenu }
        'TuneUp'      { Invoke-FullTuneUp -WhatIf:$WhatIf }
    }
    return
}

# Default: Interactive menu mode
Invoke-MenuLoop -RiskLevel $Risk -WhatIf:$WhatIf
