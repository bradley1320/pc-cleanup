# ==============================================================================
# PC Cleanup v2 -- TaskHandler.ps1
# Scheduled task enable/disable operations.
# Validates task existence before operating.
# ==============================================================================

function Set-PCCleanupScheduledTask {
    <#
    .SYNOPSIS
        Enables or disables a Windows scheduled task.
    .DESCRIPTION
        Validates that the task exists at the specified path before
        attempting to change its state. Logs the operation result.
    .PARAMETER TaskPath
        The full scheduled task path (e.g. '\Microsoft\Windows\...').
    .PARAMETER Enabled
        $true to enable, $false to disable.
    .EXAMPLE
        Set-PCCleanupScheduledTask -TaskPath '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator' -Enabled $false
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TaskPath,

        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    try {
        # Split full path into folder and task name
        $folder = Split-Path $TaskPath -Parent
        $taskName = Split-Path $TaskPath -Leaf

        # Normalize folder path -- Get-ScheduledTask expects trailing backslash
        if (-not $folder.EndsWith('\')) {
            $folder = "$folder\"
        }

        $task = Get-ScheduledTask -TaskPath $folder -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -eq $task) {
            Write-Skip "Scheduled task '$TaskPath' not found on this system -- skipping."
            return
        }

        if ($Enabled) {
            Enable-ScheduledTask -TaskPath $folder -TaskName $taskName | Out-Null
            Write-Success "Enabled scheduled task '$taskName'"
        }
        else {
            Disable-ScheduledTask -TaskPath $folder -TaskName $taskName | Out-Null
            Write-Success "Disabled scheduled task '$taskName'"
        }
        Write-Log "ScheduledTask: Set '$TaskPath' Enabled=$Enabled"
    }
    catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        Write-Err -Message "Cannot modify scheduled task '$TaskPath'" -Cause 'Access denied - task is protected.' -Fix 'Run as Administrator.'
    }
    catch {
        Write-Err -Message "Failed to modify scheduled task '$TaskPath'" -Cause $_.Exception.Message -Fix 'Check that the task path is correct and run as Administrator.'
    }
}
