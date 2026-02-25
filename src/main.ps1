# ==============================================================================
# PC Cleanup v2 — main.ps1
# Entry point: parameter parsing, module loading, UI launch.
# Built with Claude Code (Anthropic). Open source and fully auditable.
# ==============================================================================

[CmdletBinding()]
param(
    # Apply a preset profile (Safe, Gaming, Privacy, Custom)
    [ValidateSet('Safe', 'Gaming', 'Privacy', 'Custom')]
    [string]$Profile,

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
# Load order is critical: core (01-05) -> handlers -> modules -> ui
# All paths resolved via $PSScriptRoot — never relative to working directory

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

# --- Entry Point ---
# CLI mode vs interactive mode dispatch

throw "Not implemented - Phase 5 wires up CLI parsing and menu dispatch"
