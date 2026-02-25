# ==============================================================================
# PC Cleanup v2 — ServiceHandler.ps1
# Service start/stop and startup type changes.
# Uses Stop-Service + Set-Service for immediate effect (not registry-only).
# ==============================================================================

function Set-PCCleanupService {
    <#
    .SYNOPSIS
        Changes a service's startup type, optionally stopping it first.
    .DESCRIPTION
        Validates the service exists before operating. Uses direct service
        management for immediate effect. Post-apply verification checks
        that the service actually changed state (some protected services
        silently revert). Catches Access Denied for protected services.
    .PARAMETER Name
        The service name (e.g. 'DiagTrack').
    .PARAMETER StartupType
        The target startup type: Automatic, Manual, Disabled.
    .PARAMETER StopFirst
        If specified, stops the service before changing startup type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Automatic', 'Manual', 'Disabled')]
        [string]$StartupType,

        [switch]$StopFirst
    )

    throw "Not implemented"
}
