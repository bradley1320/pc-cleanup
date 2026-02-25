# ==============================================================================
# PC Cleanup v2 — 02-SystemInfo.ps1
# System capability detection using feature detection over version checking
# ==============================================================================

function Get-OSBuild {
    <#
    .SYNOPSIS
        Returns the current Windows build number.
    .DESCRIPTION
        Used for minBuild/maxBuild gating in the TweakEngine.
        Reads from the registry for accuracy.
    .OUTPUTS
        [int] Windows build number (e.g. 22631 for Win11 23H2).
    #>
    [CmdletBinding()]
    param()

    throw "Not implemented"
}

function Test-IsSSD {
    <#
    .SYNOPSIS
        Checks if a given drive is an SSD.
    .DESCRIPTION
        Uses Get-PhysicalDisk MediaType to detect drive type.
        Used to skip HDD-specific tweaks on SSDs.
    .PARAMETER DriveLetter
        The drive letter to check (e.g. 'C').
    .OUTPUTS
        [bool] $true if SSD, $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [char]$DriveLetter
    )

    throw "Not implemented"
}

function Get-ChassisType {
    <#
    .SYNOPSIS
        Detects whether the system is a Desktop, Laptop, or Tablet.
    .DESCRIPTION
        Uses Win32_SystemEnclosure ChassisTypes WMI property.
        Used to warn about battery impact for power plan changes.
    .OUTPUTS
        [string] 'Desktop', 'Laptop', or 'Tablet'.
    #>
    [CmdletBinding()]
    param()

    throw "Not implemented"
}

function Test-FeatureExists {
    <#
    .SYNOPSIS
        Checks if a specific Windows feature/registry key exists.
    .DESCRIPTION
        Feature detection pattern: ask "does this exist?" rather than
        checking OS version. Makes the tool forward-compatible.
    .PARAMETER RegistryPath
        The full registry path to check.
    .PARAMETER ValueName
        The registry value name to check for.
    .OUTPUTS
        [bool] $true if the feature exists, $false otherwise.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryPath,

        [string]$ValueName
    )

    throw "Not implemented"
}
