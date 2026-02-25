# ==============================================================================
# PC Cleanup v2 — 05-UndoManager.ps1
# Tracks applied tweaks with full original state captured at apply time.
# Enables per-tweak and bulk undo. Persists to undo_log.json between sessions.
# ==============================================================================

# Undo log lives at %LOCALAPPDATA%\PCCleanup\undo_log.json
$script:UndoLogDir = Join-Path $env:LOCALAPPDATA 'PCCleanup'
$script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'

function Register-AppliedTweak {
    <#
    .SYNOPSIS
        Records a tweak application with its original system state.
    .DESCRIPTION
        Captures the ACTUAL current system state (not hardcoded defaults)
        for each change and appends a full undo record to the log. This
        ensures correct undo even when the user had custom settings.
    .PARAMETER Name
        The TweakID that was applied.
    .PARAMETER Changes
        Array of change records, each containing Type (Registry/Service/
        ScheduledTask), the target path/name, and the original value.
    .PARAMETER Timestamp
        When the tweak was applied.
    .PARAMETER Category
        The tweak category (Privacy, Performance, etc.).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [array]$Changes,

        [datetime]$Timestamp = (Get-Date),

        [string]$Category
    )

    throw "Not implemented"
}

function Get-AppliedTweaks {
    <#
    .SYNOPSIS
        Returns list of currently applied (undoable) tweaks.
    .DESCRIPTION
        Reads the undo log and returns metadata for each applied tweak
        including name, category, timestamp, and OS build at apply time.
    .OUTPUTS
        [PSCustomObject[]] Array of applied tweak records.
    #>
    [CmdletBinding()]
    param()

    throw "Not implemented"
}

function Invoke-UndoTweak {
    <#
    .SYNOPSIS
        Undoes a single applied tweak using stored original values.
    .DESCRIPTION
        Reads the undo log entry for the specified tweak and restores
        each changed value to its original state. Warns if the OS build
        has changed since the tweak was applied.
    .PARAMETER Name
        The TweakID to undo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    throw "Not implemented"
}

function Invoke-UndoAll {
    <#
    .SYNOPSIS
        Undoes all applied tweaks in reverse chronological order.
    .DESCRIPTION
        Iterates through the undo log in reverse order and restores
        each tweak. Used for full system restoration.
    #>
    [CmdletBinding()]
    param()

    throw "Not implemented"
}
