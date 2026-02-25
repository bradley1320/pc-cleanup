# ==============================================================================
# PC Cleanup v2 — SystemReport.ps1
# Before/after metrics collection and comparison.
# Uses Event ID 100 for boot timing with CIM fallback.
# ==============================================================================

function Get-SystemSnapshot {
    <#
    .SYNOPSIS
        Collects a point-in-time system metrics snapshot.
    .DESCRIPTION
        Captures boot time (Event ID 100 from Diagnostics-Performance log,
        with CIM_OperatingSystem fallback), process count, free disk space,
        and startup program count.
    .OUTPUTS
        [PSCustomObject] Snapshot with BootTime, BootTimeSource, ProcessCount,
        FreeDiskSpace, StartupCount, and Timestamp.
    #>
    [CmdletBinding()]
    param()

    throw "Not implemented"
}

function Save-SystemSnapshot {
    <#
    .SYNOPSIS
        Saves a snapshot to disk with a label.
    .DESCRIPTION
        Persists the snapshot to %LOCALAPPDATA%\PCCleanup\snapshots\ for
        later comparison (before vs after).
    .PARAMETER Label
        A label for the snapshot (e.g. 'Before', 'After').
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label
    )

    throw "Not implemented"
}

function Compare-Snapshots {
    <#
    .SYNOPSIS
        Compares before and after snapshots and displays deltas.
    .DESCRIPTION
        Loads saved snapshots, calculates differences, and displays a
        formatted comparison table. Notes data source differences
        (Event ID 100 vs WMI) in the output.
    #>
    [CmdletBinding()]
    param()

    throw "Not implemented"
}
