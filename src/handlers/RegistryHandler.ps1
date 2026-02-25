# ==============================================================================
# PC Cleanup v2 — RegistryHandler.ps1
# All registry read/write operations with strict type casting.
# Called by TweakEngine — never directly by modules.
# ==============================================================================

function Set-PCCleanupRegistry {
    <#
    .SYNOPSIS
        Sets a registry value with strict type enforcement.
    .DESCRIPTION
        Creates the key path if missing, sets the value with explicit type
        casting based on the type parameter. Handles the <RemoveEntry> sentinel
        for undo operations. Catches TrustedInstaller Access Denied gracefully.

        Type casting is critical: PowerShell 5.1 ConvertFrom-Json infers types
        loosely, so a JSON integer may become System.Double, causing Set-ItemProperty
        to write REG_SZ instead of REG_DWORD. This handler always casts explicitly.
    .PARAMETER Path
        The full registry path (e.g. 'HKLM:\SOFTWARE\...').
    .PARAMETER Name
        The registry value name.
    .PARAMETER Value
        The value to set. Use '<RemoveEntry>' to delete the value.
    .PARAMETER Type
        The registry value type: DWord, QWord, String, ExpandString, MultiString, Binary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Value,

        [Parameter(Mandatory)]
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')]
        [string]$Type
    )

    throw "Not implemented"
}

function Get-PCCleanupRegistryValue {
    <#
    .SYNOPSIS
        Reads the current value and type of a registry entry.
    .DESCRIPTION
        Used by TweakEngine to capture the original state before applying
        a tweak. Returns both the value and its type for accurate undo.
    .PARAMETER Path
        The full registry path.
    .PARAMETER Name
        The registry value name.
    .OUTPUTS
        [PSCustomObject] with Value, Type, and Exists properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    throw "Not implemented"
}
