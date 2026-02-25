# ==============================================================================
# PC Cleanup v2 -- 06-SafeFileOps.ps1
# Safe file operation infrastructure for cleanup modules.
# Resolves all 5 hard blockers from Phase 2 security audit:
#   HB-1: Junction/reparse point detection (Test-IsReparsePoint, Remove-SafeDirectory)
#   HB-2: Application-level WhatIf (Remove-CleanupItem -- never delegates to PS -WhatIf)
#   HB-3: Path allowlist enforcement (Test-PathWithinAllowlist)
#   HB-4: Pre-deletion manifest (New-CleanupManifest)
#   HB-5: TOCTOU mitigation (re-validate at deletion time, not just scan time)
# ==============================================================================

# Hardcoded allowed cleanup roots -- every deletion must pass this check
$script:AllowedCleanupRoots = @()
$script:DynamicBrowserRoots = @()

function Initialize-AllowedCleanupRoots {
    <#
    .SYNOPSIS
        Initializes the allowed cleanup root paths.
    .DESCRIPTION
        Builds the static allowlist of directories where file deletion is
        permitted. Called once when the module loads. Browser cache paths
        are added dynamically via Add-BrowserCleanupRoot.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Roots is the natural term for a list of root paths')]
    [CmdletBinding()]
    param()

    $script:AllowedCleanupRoots = @(
        [System.IO.Path]::GetFullPath($env:TEMP)
        [System.IO.Path]::GetFullPath("$env:SystemRoot\Temp")
        [System.IO.Path]::GetFullPath("$env:SystemRoot\Prefetch")
        [System.IO.Path]::GetFullPath("$env:SystemRoot\SoftwareDistribution\Download")
    )
}

function Add-BrowserCleanupRoot {
    <#
    .SYNOPSIS
        Adds a validated browser cache path to the dynamic allowlist.
    .DESCRIPTION
        Browser cache paths are added at runtime after validation.
        Each path must exist and resolve to a real directory (not a reparse point).
    .PARAMETER Path
        The browser cache directory path to allow.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolved = [System.IO.Path]::GetFullPath($Path)

    # Only add if the path actually exists and is not a reparse point
    if (Test-Path -LiteralPath $resolved) {
        if (-not (Test-IsReparsePoint -Path $resolved)) {
            if ($resolved -notin $script:DynamicBrowserRoots) {
                $script:DynamicBrowserRoots += $resolved
            }
        }
        else {
            Write-Log "SECURITY: Refused to add reparse point as browser cleanup root: $resolved"
        }
    }
}

function Test-IsReparsePoint {
    <#
    .SYNOPSIS
        Checks if a path is a reparse point (junction, symlink, mount point).
    .DESCRIPTION
        Uses .NET FileAttributes to detect the ReparsePoint flag. This is
        the critical check that prevents junction-based arbitrary file deletion
        attacks (CVE-2025-21420 pattern).
    .PARAMETER Path
        The file or directory path to check.
    .OUTPUTS
        [bool] $true if the path is a reparse point, $false otherwise.
    .EXAMPLE
        Test-IsReparsePoint -Path 'C:\Users\Public\junction'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        $item = [System.IO.FileInfo]::new($Path)
        if (-not $item.Exists) {
            $item = [System.IO.DirectoryInfo]::new($Path)
            if (-not $item.Exists) {
                return $false
            }
        }
        return $item.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)
    }
    catch {
        # If we can't read attributes, treat as suspicious
        Write-Log "SECURITY: Could not read attributes for '$Path': $($_.Exception.Message)"
        return $true
    }
}

function Test-PathWithinAllowlist {
    <#
    .SYNOPSIS
        Validates that a resolved path falls within an allowed cleanup root.
    .DESCRIPTION
        Defense-in-depth: even if the reparse point check fails due to a race
        condition, the allowlist prevents operations on system directories.
        Every file deletion must pass this check.
    .PARAMETER Path
        The path to validate.
    .OUTPUTS
        [bool] $true if the path is within an allowed root, $false otherwise.
    .EXAMPLE
        Test-PathWithinAllowlist -Path "$env:TEMP\somefile.tmp"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    try {
        $resolved = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        return $false
    }

    $allRoots = $script:AllowedCleanupRoots + $script:DynamicBrowserRoots

    foreach ($root in $allRoots) {
        if ($resolved.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
            # Prevent partial prefix matches: C:\Temp matching C:\Temporary
            # The path must either equal the root or have a path separator after the root
            if ($resolved.Length -eq $root.Length) { return $true }
            $charAfterRoot = $resolved[$root.Length]
            if ($charAfterRoot -eq '\' -or $charAfterRoot -eq '/') { return $true }
        }
    }

    return $false
}

function Test-IsCloudPlaceholder {
    <#
    .SYNOPSIS
        Detects OneDrive Files On Demand placeholders.
    .DESCRIPTION
        Files with FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS (0x00400000) or
        FILE_ATTRIBUTE_RECALL_ON_OPEN (0x00040000) are cloud placeholders.
        Deleting them triggers cloud sync deletion across all devices and
        reports inaccurate space recovered (zero local bytes).
    .PARAMETER Item
        A FileSystemInfo object to check.
    .OUTPUTS
        [bool] $true if the item is a cloud placeholder.
    .EXAMPLE
        $file = [System.IO.FileInfo]::new('C:\Users\me\OneDrive\doc.txt')
        Test-IsCloudPlaceholder -Item $file
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    # Use raw integer bitwise AND -- PS 5.1's FileAttributes enum doesn't
    # include these newer flags (FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS,
    # FILE_ATTRIBUTE_RECALL_ON_OPEN), so casting to the enum throws.
    $rawAttributes = [int]$Item.Attributes
    $recallOnDataAccess = 0x00400000
    $recallOnOpen       = 0x00040000
    return (($rawAttributes -band $recallOnDataAccess) -ne 0) -or (($rawAttributes -band $recallOnOpen) -ne 0)
}

function Get-SafePath {
    <#
    .SYNOPSIS
        Applies \\?\ prefix for long path support.
    .DESCRIPTION
        PowerShell 5.1 inherits MAX_PATH (260 chars). The \\?\ prefix
        enables the extended-length path API, supporting paths up to 32,767
        characters. Only applies to absolute paths that don't already have
        the prefix.
    .PARAMETER Path
        The path to prefix.
    .OUTPUTS
        [string] The path with \\?\ prefix if applicable.
    .EXAMPLE
        Get-SafePath -Path 'C:\very\long\path'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    # Already has extended prefix
    if ($Path.StartsWith('\\?\')) { return $Path }

    # Only apply to absolute paths
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return "\\?\$Path"
    }

    return $Path
}

function New-CleanupManifest {
    <#
    .SYNOPSIS
        Generates a pre-deletion JSON manifest for audit trail.
    .DESCRIPTION
        Before deleting any files, records every targeted path, size, and
        timestamp to a JSON manifest at %LOCALAPPDATA%\PCCleanup\logs\.
        This is the safety net for file deletion -- irreversible operations
        need a paper trail.
    .PARAMETER Targets
        Array of target objects with Name, Path, FileCount, Size properties.
    .PARAMETER TotalBytes
        Total bytes estimated for cleanup.
    .OUTPUTS
        [string] The path to the created manifest file.
    .EXAMPLE
        New-CleanupManifest -Targets $targets -TotalBytes 1048576
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Creates audit log files only -- not a destructive operation')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Targets,

        [long]$TotalBytes = 0
    )

    $logDir = Join-Path $env:LOCALAPPDATA 'PCCleanup\logs'
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $manifestPath = Join-Path $logDir "cleanup_manifest_$timestamp.json"

    $manifest = [PSCustomObject]@{
        CreatedAt     = (Get-Date).ToString('o')
        OSBuild       = Get-OSBuild
        TotalBytes    = $TotalBytes
        TargetCount   = $Targets.Count
        Targets       = @($Targets | ForEach-Object {
            [PSCustomObject]@{
                Name      = $_.Name
                Path      = $_.Path
                FileCount = $_.FileCount
                Size      = $_.Size
            }
        })
    }

    $manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding UTF8
    Write-Log "Cleanup manifest created: $manifestPath"
    return $manifestPath
}

function Remove-SafeDirectory {
    <#
    .SYNOPSIS
        Reparse-point-aware recursive directory deletion.
    .DESCRIPTION
        Uses .NET EnumerateFileSystemInfos() to iterate directory contents.
        Checks ReparsePoint attribute on EVERY directory before recursing.
        Never uses Remove-Item -Recurse (PS follows junctions during
        recursive deletion -- GitHub issues #621, #16664, #19714).

        TOCTOU mitigation: re-validates reparse attributes at deletion time,
        not just at scan time.
    .PARAMETER Path
        The directory to clean.
    .PARAMETER WhatIf
        Application-level WhatIf -- performs ONLY read operations.
        Never delegates to PowerShell's native -WhatIf (PS bug: -WhatIf
        on junctions actually deletes the reparse point).
    .OUTPUTS
        [PSCustomObject] With properties: DeletedFiles, DeletedBytes, SkippedFiles, Errors.
    .EXAMPLE
        Remove-SafeDirectory -Path "$env:TEMP\cache"
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'WhatIf used in conditional branches')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Application-level WhatIf -- intentionally not using ShouldProcess')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$WhatIf
    )

    $stats = [PSCustomObject]@{
        DeletedFiles  = 0
        DeletedBytes  = [long]0
        SkippedFiles  = 0
        Errors        = 0
    }

    # Allowlist check at deletion time (TOCTOU mitigation)
    if (-not (Test-PathWithinAllowlist -Path $Path)) {
        Write-Log "SECURITY: Path '$Path' is outside allowed cleanup roots. Refusing to operate."
        Write-Warn "Blocked: '$Path' is not in the allowed cleanup directory list."
        return $stats
    }

    $dirInfo = [System.IO.DirectoryInfo]::new($Path)
    if (-not $dirInfo.Exists) { return $stats }

    # Re-check reparse point at deletion time (TOCTOU mitigation for HB-5)
    if ($dirInfo.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
        Write-Log "SECURITY: Refused to recurse into reparse point at deletion time: $Path"
        Write-Warn "Skipping reparse point (junction/symlink): $Path"
        $stats.SkippedFiles++
        return $stats
    }

    try {
        foreach ($entry in $dirInfo.EnumerateFileSystemInfos()) {
            if ($entry.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
                Write-Log "SECURITY: Skipped reparse point: $($entry.FullName)"
                $stats.SkippedFiles++
                continue
            }

            # Skip cloud placeholders
            if (-not ($entry -is [System.IO.DirectoryInfo])) {
                if (Test-IsCloudPlaceholder -Item $entry) {
                    Write-Log "Skipped cloud placeholder: $($entry.FullName)"
                    $stats.SkippedFiles++
                    continue
                }
            }

            if ($entry -is [System.IO.DirectoryInfo]) {
                # Recurse into subdirectories
                $subStats = Remove-SafeDirectory -Path $entry.FullName -WhatIf:$WhatIf
                $stats.DeletedFiles  += $subStats.DeletedFiles
                $stats.DeletedBytes  += $subStats.DeletedBytes
                $stats.SkippedFiles  += $subStats.SkippedFiles
                $stats.Errors        += $subStats.Errors

                # Try to remove the now-empty directory (non-WhatIf only)
                if (-not $WhatIf) {
                    try {
                        # Only remove if empty -- re-check reparse before removing
                        $refreshed = [System.IO.DirectoryInfo]::new($entry.FullName)
                        if ($refreshed.Exists -and -not $refreshed.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
                            $remaining = @($refreshed.EnumerateFileSystemInfos())
                            if ($remaining.Count -eq 0) {
                                $refreshed.Delete()
                            }
                        }
                    }
                    catch [System.IO.IOException] {
                        # Directory not empty or locked -- skip silently
                        $null = $_
                    }
                    catch [System.UnauthorizedAccessException] {
                        Write-Log "Access denied removing directory: $($entry.FullName)"
                        $stats.Errors++
                    }
                    catch {
                        $stats.Errors++
                    }
                }
            }
            else {
                # File deletion
                if ($WhatIf) {
                    # Application-level WhatIf -- ONLY read operations
                    $stats.DeletedFiles++
                    try { $stats.DeletedBytes += $entry.Length } catch { $null = $_ }
                }
                else {
                    try {
                        $fileLen = $entry.Length
                        $entry.Delete()
                        $stats.DeletedFiles++
                        $stats.DeletedBytes += $fileLen
                    }
                    catch [System.IO.IOException] {
                        # File locked -- expected, skip silently
                        $stats.SkippedFiles++
                    }
                    catch [System.UnauthorizedAccessException] {
                        Write-Log "Access denied: $($entry.FullName)"
                        $stats.SkippedFiles++
                    }
                    catch {
                        Write-Log "Could not delete: $($entry.FullName) - $($_.Exception.Message)"
                        $stats.Errors++
                    }
                }
            }
        }
    }
    catch [System.IO.DirectoryNotFoundException] {
        # Directory disappeared between check and enumerate -- race condition, safe to ignore
        $null = $_
    }
    catch [System.IO.PathTooLongException] {
        Write-Log "Path too long in directory: $Path"
        Write-Warn "Some files skipped due to path length exceeding system limits."
        $stats.Errors++
    }
    catch {
        Write-Log "Error enumerating '$Path': $($_.Exception.Message)"
        $stats.Errors++
    }

    return $stats
}

function Remove-CleanupItem {
    <#
    .SYNOPSIS
        Safely removes a single file or directory with all security checks.
    .DESCRIPTION
        Application-level WhatIf that NEVER delegates to PowerShell's native
        -WhatIf (PS bug: -WhatIf destroys junctions -- GitHub #16664, #19714).
        WhatIf branch performs ONLY read operations.

        Validates path against allowlist and checks reparse points before any
        deletion. For directories, delegates to Remove-SafeDirectory.
    .PARAMETER Path
        The file or directory to remove.
    .PARAMETER WhatIf
        Preview mode -- performs zero filesystem modifications.
    .OUTPUTS
        [PSCustomObject] With properties: DeletedFiles, DeletedBytes, SkippedFiles, Errors.
    .EXAMPLE
        Remove-CleanupItem -Path "$env:TEMP\cache\file.tmp"
        Remove-CleanupItem -Path "$env:TEMP\cache" -WhatIf
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'WhatIf used in conditional branches')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Application-level WhatIf -- intentionally not using ShouldProcess')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$WhatIf
    )

    $stats = [PSCustomObject]@{
        DeletedFiles  = 0
        DeletedBytes  = [long]0
        SkippedFiles  = 0
        Errors        = 0
    }

    # Allowlist enforcement
    if (-not (Test-PathWithinAllowlist -Path $Path)) {
        Write-Log "SECURITY: Blocked deletion outside allowlist: $Path"
        Write-Warn "Blocked: '$Path' is not in the allowed cleanup directory list."
        $stats.SkippedFiles++
        return $stats
    }

    # Reparse point check
    if (Test-IsReparsePoint -Path $Path) {
        Write-Log "SECURITY: Refused to delete reparse point: $Path"
        Write-Warn "Skipping reparse point (junction/symlink): $Path"
        $stats.SkippedFiles++
        return $stats
    }

    # Directory -- delegate to Remove-SafeDirectory
    if (Test-Path -LiteralPath $Path -PathType Container) {
        return Remove-SafeDirectory -Path $Path -WhatIf:$WhatIf
    }

    # File
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $fileInfo = [System.IO.FileInfo]::new($Path)

        # Cloud placeholder check
        if (Test-IsCloudPlaceholder -Item $fileInfo) {
            Write-Log "Skipped cloud placeholder: $Path"
            $stats.SkippedFiles++
            return $stats
        }

        if ($WhatIf) {
            $stats.DeletedFiles = 1
            try { $stats.DeletedBytes = $fileInfo.Length } catch { $null = $_ }
            return $stats
        }

        try {
            $len = $fileInfo.Length
            $fileInfo.Delete()
            $stats.DeletedFiles = 1
            $stats.DeletedBytes = $len
        }
        catch [System.IO.IOException] {
            $stats.SkippedFiles = 1
        }
        catch [System.UnauthorizedAccessException] {
            Write-Log "Access denied: $Path"
            $stats.SkippedFiles = 1
        }
        catch {
            Write-Log "Could not delete '$Path': $($_.Exception.Message)"
            $stats.Errors = 1
        }
    }

    return $stats
}

# Initialize the allowlist when this module loads
Initialize-AllowedCleanupRoots
