# ==============================================================================
# PC Cleanup v2 -- ServiceHandler.ps1
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

    try {
        $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            Write-Warn "Service '$Name' not found on this system -- skipping."
            return
        }

        if ($StopFirst -and $svc.Status -eq 'Running') {
            Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
            Write-Log "Service: Stopped '$Name'"
        }

        Set-Service -Name $Name -StartupType $StartupType
        Write-Log "Service: Set '$Name' startup type to '$StartupType'"

        # Post-apply verification -- some protected services silently revert
        $verify = Get-Service -Name $Name
        if ($verify.StartType -ne $StartupType) {
            Write-Warn "Service '$Name' may have reverted -- protected by Windows. Requested '$StartupType', actual '$($verify.StartType)'."
        }
        else {
            Write-Success "Service '$Name' set to '$StartupType'"
        }
    }
    catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        Write-Err -Message "Cannot modify service '$Name'" -Cause 'Access denied - service is protected by Windows.' -Fix 'Run as Administrator, or check with your IT department.'
    }
    catch {
        Write-Err -Message "Failed to modify service '$Name'" -Cause $_.Exception.Message -Fix 'Run as Administrator, or check that the service name is correct.'
    }
}
