# ==============================================================================
# PC Cleanup v2 -- ScriptHandler.ps1
# Executes arbitrary PowerShell script blocks defined in tweaks.json.
# Escape hatch for operations that can't be expressed as registry/service/task.
# ==============================================================================

function Invoke-PCCleanupScript {
    <#
    .SYNOPSIS
        Executes a PowerShell script block from a tweak definition.
    .DESCRIPTION
        Script blocks are stored as strings in tweaks.json. This handler
        creates a scriptblock from the string and invokes it. Used for
        complex operations like DISM cleanup, browser cache clearing, etc.
    .PARAMETER ScriptBlock
        The PowerShell code to execute, as a string.
    .EXAMPLE
        Invoke-PCCleanupScript -ScriptBlock 'Write-Host "Hello"'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ScriptBlock
    )

    if ([string]::IsNullOrWhiteSpace($ScriptBlock)) {
        Write-Log 'Script: Skipping empty script block'
        return
    }

    try {
        Write-Log "Script: Executing script block: $ScriptBlock"
        $sb = [scriptblock]::Create($ScriptBlock)
        & $sb
        Write-Log "Script: Script block completed successfully"
    }
    catch {
        Write-Err -Message 'Script block execution failed' -Cause $_.Exception.Message -Fix 'Check the invokeScript definition in tweaks.json.'
        Write-Log "Script: FAILED -- $($_.Exception.Message) -- Block: $ScriptBlock"
    }
}
