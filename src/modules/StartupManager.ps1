# ==============================================================================
# PC Cleanup v2 -- StartupManager.ps1
# View and manage startup programs with publisher, description, and risk context.
# Cross-references apps-critical.json and apps-bloat.json for risk indicators.
# ==============================================================================

function Get-StartupPrograms {
    <#
    .SYNOPSIS
        Scans and returns all startup programs with metadata.
    .DESCRIPTION
        Scans registry Run keys (HKCU + HKLM) and startup folders.
        For each entry: resolves file path, extracts publisher and
        description from file properties. Cross-references against
        apps-critical.json and apps-bloat.json. Handles orphaned entries
        (missing executables) gracefully.
    .OUTPUTS
        [PSCustomObject[]] Array with Name, Publisher, Description, Path, Source, Risk.
    #>
    [CmdletBinding()]
    param()

    throw "Not implemented"
}

function Disable-StartupProgram {
    <#
    .SYNOPSIS
        Disables a startup program and registers undo.
    .DESCRIPTION
        Removes the startup entry from registry or startup folder.
        Records the original state in UndoManager for restoration.
    .PARAMETER Name
        The name of the startup program to disable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    throw "Not implemented"
}

function Enable-StartupProgram {
    <#
    .SYNOPSIS
        Re-enables a previously disabled startup program.
    .DESCRIPTION
        Restores the startup entry from undo data.
    .PARAMETER Name
        The name of the startup program to re-enable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    throw "Not implemented"
}
