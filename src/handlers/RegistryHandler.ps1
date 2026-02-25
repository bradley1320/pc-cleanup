# ==============================================================================
# PC Cleanup v2 -- RegistryHandler.ps1
# All registry read/write operations with strict type casting.
# Called by TweakEngine -- never directly by modules.
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
    [CmdletBinding(SupportsShouldProcess)]
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

    try {
        # Handle <RemoveEntry> sentinel -- delete the value
        if ($Value -eq '<RemoveEntry>') {
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue
            Write-Log "Registry: Removed '$Name' from '$Path'"
            return
        }

        # Create key path if missing
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
            Write-Log "Registry: Created key '$Path'"
        }

        # Strict type casting -- never rely on PowerShell's default inference
        $castValue = switch ($Type) {
            'DWord'        { [UInt32]$Value }
            'QWord'        { [UInt64]$Value }
            'String'       { [string]$Value }
            'ExpandString' { [string]$Value }
            'MultiString'  { [string[]]$Value }
            'Binary'       { [byte[]]$Value }
        }

        Set-ItemProperty -Path $Path -Name $Name -Value $castValue -Type $Type -Force
        Write-Log "Registry: Set '$Path\$Name' = $Value ($Type)"
    }
    catch [System.UnauthorizedAccessException], [System.Security.SecurityException] {
        Write-Warn "Cannot modify '$Path\$Name' -- this key is protected by TrustedInstaller. Use Group Policy instead."
        Write-Log "Registry: Access Denied on '$Path\$Name' (TrustedInstaller protected)"
    }
    catch {
        $errMsg = "Failed to set registry value '$Path\$Name'"
        Write-Err -Message $errMsg -Cause $_.Exception.Message -Fix 'Run as Administrator, or check that the registry path is valid.'
    }
}

function Get-PCCleanupRegistryValue {
    <#
    .SYNOPSIS
        Reads the current value and type of a registry entry.
    .DESCRIPTION
        Used by TweakEngine to capture the original state before applying
        a tweak. Uses .NET registry API for accurate type detection.
    .PARAMETER Path
        The full registry path.
    .PARAMETER Name
        The registry value name.
    .OUTPUTS
        [PSCustomObject] with Value, Type, and Exists properties.
    .EXAMPLE
        Get-PCCleanupRegistryValue -Path 'HKCU:\Software\Microsoft\Windows\...' -Name 'Enabled'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        if (-not (Test-Path $Path)) {
            return [PSCustomObject]@{ Value = $null; Type = $null; Exists = $false }
        }

        # Use .NET registry API for accurate type detection
        # Convert PS drive path to .NET hive + subkey
        $hiveName = $Path.Split(':')[0]
        $subKey = $Path.Split('\', 2)[1].TrimStart('\')

        $hive = switch ($hiveName) {
            'HKLM' { [Microsoft.Win32.Registry]::LocalMachine }
            'HKCU' { [Microsoft.Win32.Registry]::CurrentUser }
            'HKCR' { [Microsoft.Win32.Registry]::ClassesRoot }
            'HKU'  { [Microsoft.Win32.Registry]::Users }
            'HKCC' { [Microsoft.Win32.Registry]::CurrentConfig }
            default {
                # Fallback for PS-style paths
                return [PSCustomObject]@{ Value = $null; Type = $null; Exists = $false }
            }
        }

        $key = $hive.OpenSubKey($subKey, $false)
        if ($null -eq $key) {
            return [PSCustomObject]@{ Value = $null; Type = $null; Exists = $false }
        }

        try {
            $val = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            if ($null -eq $val -and $null -eq $key.GetValue($Name)) {
                return [PSCustomObject]@{ Value = $null; Type = $null; Exists = $false }
            }

            # Map .NET RegistryValueKind to our type names
            $kind = $key.GetValueKind($Name)
            $typeName = switch ($kind) {
                'DWord'        { 'DWord' }
                'QWord'        { 'QWord' }
                'String'       { 'String' }
                'ExpandString' { 'ExpandString' }
                'MultiString'  { 'MultiString' }
                'Binary'       { 'Binary' }
                default        { 'String' }
            }

            return [PSCustomObject]@{ Value = $val; Type = $typeName; Exists = $true }
        }
        finally {
            $key.Close()
        }
    }
    catch {
        return [PSCustomObject]@{ Value = $null; Type = $null; Exists = $false }
    }
}
