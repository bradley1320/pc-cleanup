# ==============================================================================
# PC Cleanup v2 -- 02-SystemInfo.ps1
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

    try {
        $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        [int](Get-ItemProperty -Path $regPath -Name CurrentBuildNumber).CurrentBuildNumber
    }
    catch {
        Write-Warn "Could not read OS build number: $_"
        return 0
    }
}

function Test-IsSSD {
    <#
    .SYNOPSIS
        Checks if a given drive is an SSD.
    .DESCRIPTION
        Maps DriveLetter to physical disk via Get-Partition, then checks
        Get-PhysicalDisk MediaType. Falls back to $false on error.
    .PARAMETER DriveLetter
        The drive letter to check (e.g. 'C').
    .OUTPUTS
        [bool] $true if SSD, $false otherwise.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'DriveLetter', Justification = 'Used as cmdlet argument')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [char]$DriveLetter
    )

    try {
        $partition = Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop
        $disk = Get-PhysicalDisk -DeviceNumber $partition.DiskNumber -ErrorAction Stop
        return $disk.MediaType -eq 'SSD'
    }
    catch {
        # Can't determine drive type -- assume not SSD (conservative default)
        return $false
    }
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

    try {
        $chassisType = (Get-CimInstance Win32_SystemEnclosure).ChassisTypes[0]
        # Laptop chassis types per SMBIOS spec
        if ($chassisType -in 8, 9, 10, 11, 12, 13, 14, 30, 31, 32) {
            return 'Laptop'
        }
        if ($chassisType -eq 17) {
            return 'Tablet'
        }
        return 'Desktop'
    }
    catch {
        return 'Desktop'
    }
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
        Optional registry value name to check for. If omitted, checks
        whether the key itself exists.
    .OUTPUTS
        [bool] $true if the feature exists, $false otherwise.
    .EXAMPLE
        Test-FeatureExists -RegistryPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Params used as cmdlet arguments')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RegistryPath,

        [string]$ValueName
    )

    try {
        if (-not (Test-Path $RegistryPath)) {
            return $false
        }
        if ([string]::IsNullOrEmpty($ValueName)) {
            return $true
        }
        $prop = Get-ItemProperty -Path $RegistryPath -Name $ValueName -ErrorAction SilentlyContinue
        return $null -ne $prop
    }
    catch {
        return $false
    }
}
