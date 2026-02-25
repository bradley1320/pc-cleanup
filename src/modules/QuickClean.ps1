# ==============================================================================
# PC Cleanup v2 -- QuickClean.ps1
# Temporary/cache file cleanup with preview and user selection.
# Uses SafeFileOps exclusively for ALL file operations.
# Flow: scan --> preview with sizes --> user selects --> create manifest --> execute
# ==============================================================================

function Get-BrowserProfiles {
    <#
    .SYNOPSIS
        Detects installed browsers and their cache/profile paths.
    .DESCRIPTION
        Dynamically detects Chrome, Edge, Firefox, Brave, Opera, and Arc.
        Enumerates profiles within each browser. Checks standard install
        locations rather than hardcoding user-specific paths. Registers
        discovered cache paths with SafeFileOps allowlist.
    .OUTPUTS
        [PSCustomObject[]] Array of browser profiles with Browser, Profile, CachePath, and DataPath.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Returns multiple browser profiles')]
    [CmdletBinding()]
    param()

    $results = @()
    $localAppData = $env:LOCALAPPDATA
    $appData = $env:APPDATA

    # Chromium-based browsers share the same profile structure
    $chromiumBrowsers = @(
        @{ Name = 'Chrome';  BasePath = Join-Path $localAppData 'Google\Chrome\User Data' }
        @{ Name = 'Edge';    BasePath = Join-Path $localAppData 'Microsoft\Edge\User Data' }
        @{ Name = 'Brave';   BasePath = Join-Path $localAppData 'BraveSoftware\Brave-Browser\User Data' }
        @{ Name = 'Opera';   BasePath = Join-Path $localAppData 'Opera Software\Opera Stable' }
        @{ Name = 'Opera GX'; BasePath = Join-Path $localAppData 'Opera Software\Opera GX Stable' }
        @{ Name = 'Arc';     BasePath = Join-Path $localAppData 'Arc\User Data' }
        @{ Name = 'Vivaldi'; BasePath = Join-Path $localAppData 'Vivaldi\User Data' }
    )

    foreach ($browser in $chromiumBrowsers) {
        if (-not (Test-Path -LiteralPath $browser.BasePath)) { continue }

        # Opera stores data directly in its base path (no profile subfolders)
        if ($browser.Name -eq 'Opera' -or $browser.Name -eq 'Opera GX') {
            $cachePath = Join-Path $browser.BasePath 'Cache'
            if (Test-Path -LiteralPath $cachePath) {
                Add-BrowserCleanupRoot -Path $cachePath
                $results += [PSCustomObject]@{
                    Browser   = $browser.Name
                    Profile   = 'Default'
                    CachePath = $cachePath
                    DataPath  = $browser.BasePath
                }
            }
            # Also check Cache\Cache_Data (newer Chromium structure)
            $cacheDataPath = Join-Path $browser.BasePath 'Cache\Cache_Data'
            if ((Test-Path -LiteralPath $cacheDataPath) -and -not (Test-Path -LiteralPath $cachePath)) {
                Add-BrowserCleanupRoot -Path (Join-Path $browser.BasePath 'Cache')
                $results += [PSCustomObject]@{
                    Browser   = $browser.Name
                    Profile   = 'Default'
                    CachePath = Join-Path $browser.BasePath 'Cache'
                    DataPath  = $browser.BasePath
                }
            }
            continue
        }

        # Standard Chromium profiles: Default, Profile 1, Profile 2, etc.
        $profiles = @('Default')
        $profileDirs = Get-ChildItem -LiteralPath $browser.BasePath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^Profile \d+$' }
        if ($profileDirs) {
            $profiles += @($profileDirs | ForEach-Object { $_.Name })
        }

        foreach ($profile in $profiles) {
            $profilePath = Join-Path $browser.BasePath $profile
            if (-not (Test-Path -LiteralPath $profilePath)) { continue }

            # Chromium stores cache in Cache\Cache_Data (newer) or Cache (older)
            $cachePath = $null
            $cacheDataPath = Join-Path $profilePath 'Cache\Cache_Data'
            $cacheOldPath = Join-Path $profilePath 'Cache'
            if (Test-Path -LiteralPath $cacheDataPath) {
                $cachePath = Join-Path $profilePath 'Cache'
            }
            elseif (Test-Path -LiteralPath $cacheOldPath) {
                $cachePath = $cacheOldPath
            }

            if ($cachePath) {
                Add-BrowserCleanupRoot -Path $cachePath
                $results += [PSCustomObject]@{
                    Browser   = $browser.Name
                    Profile   = $profile
                    CachePath = $cachePath
                    DataPath  = $profilePath
                }
            }
        }
    }

    # Firefox uses a different profile structure (random profile names)
    $firefoxBase = Join-Path $appData 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $firefoxBase) {
        $ffProfiles = Get-ChildItem -LiteralPath $firefoxBase -Directory -ErrorAction SilentlyContinue
        foreach ($ffProfile in $ffProfiles) {
            $cachePath = Join-Path $ffProfile.FullName 'cache2'
            if (Test-Path -LiteralPath $cachePath) {
                Add-BrowserCleanupRoot -Path $cachePath
                $results += [PSCustomObject]@{
                    Browser   = 'Firefox'
                    Profile   = $ffProfile.Name
                    CachePath = $cachePath
                    DataPath  = $ffProfile.FullName
                }
            }
        }
    }

    return $results
}

function Get-CleanupTargets {
    <#
    .SYNOPSIS
        Scans all cleanup targets and returns their sizes.
    .DESCRIPTION
        Read-only scan of temp directories, browser caches, Windows Update
        cache, and prefetch. Returns a list of targets with file counts and
        total sizes for user preview. Uses SafeFileOps reparse point checks
        during scanning. Never follows junctions or symlinks.
    .OUTPUTS
        [PSCustomObject[]] Array of cleanup targets with Name, Path, FileCount,
        Size, Type, and RequiresAdmin properties.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Returns multiple cleanup targets')]
    [CmdletBinding()]
    param()

    $targets = @()

    # --- User Temp Files ---
    $userTemp = $env:TEMP
    if (Test-Path -LiteralPath $userTemp) {
        $scan = Measure-DirectorySafe -Path $userTemp
        $targets += [PSCustomObject]@{
            Name          = 'User Temp Files'
            Path          = $userTemp
            FileCount     = $scan.FileCount
            Size          = $scan.TotalBytes
            Type          = 'temp'
            RequiresAdmin = $false
        }
    }

    # --- Windows Temp ---
    $winTemp = "$env:SystemRoot\Temp"
    if (Test-Path -LiteralPath $winTemp) {
        $scan = Measure-DirectorySafe -Path $winTemp
        $targets += [PSCustomObject]@{
            Name          = 'Windows Temp Files'
            Path          = $winTemp
            FileCount     = $scan.FileCount
            Size          = $scan.TotalBytes
            Type          = 'temp'
            RequiresAdmin = $true
        }
    }

    # --- Windows Update Cache ---
    $wuCache = "$env:SystemRoot\SoftwareDistribution\Download"
    if (Test-Path -LiteralPath $wuCache) {
        $scan = Measure-DirectorySafe -Path $wuCache
        $targets += [PSCustomObject]@{
            Name          = 'Windows Update Cache'
            Path          = $wuCache
            FileCount     = $scan.FileCount
            Size          = $scan.TotalBytes
            Type          = 'wucache'
            RequiresAdmin = $true
        }
    }

    # --- Prefetch ---
    $prefetch = "$env:SystemRoot\Prefetch"
    if (Test-Path -LiteralPath $prefetch) {
        $scan = Measure-DirectorySafe -Path $prefetch
        $targets += [PSCustomObject]@{
            Name          = 'Prefetch Files'
            Path          = $prefetch
            FileCount     = $scan.FileCount
            Size          = $scan.TotalBytes
            Type          = 'prefetch'
            RequiresAdmin = $true
        }
    }

    # --- Browser Caches ---
    $browsers = Get-BrowserProfiles
    foreach ($browser in $browsers) {
        $scan = Measure-DirectorySafe -Path $browser.CachePath
        if ($scan.FileCount -gt 0) {
            $displayName = "$($browser.Browser) Cache"
            if ($browser.Profile -ne 'Default') {
                $displayName = "$($browser.Browser) Cache ($($browser.Profile))"
            }
            $targets += [PSCustomObject]@{
                Name          = $displayName
                Path          = $browser.CachePath
                FileCount     = $scan.FileCount
                Size          = $scan.TotalBytes
                Type          = 'browser'
                RequiresAdmin = $false
            }
        }
    }

    return $targets
}

function Measure-DirectorySafe {
    <#
    .SYNOPSIS
        Safely measures a directory's file count and total size.
    .DESCRIPTION
        Uses .NET EnumerateFileSystemInfos to count files and sum sizes
        without following reparse points. Handles locked files, access
        denied, and path-too-long errors gracefully.
    .PARAMETER Path
        The directory to measure.
    .OUTPUTS
        [PSCustomObject] With FileCount and TotalBytes properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $result = [PSCustomObject]@{
        FileCount  = 0
        TotalBytes = [long]0
    }

    $dirInfo = [System.IO.DirectoryInfo]::new($Path)
    if (-not $dirInfo.Exists) { return $result }

    # Skip if the directory itself is a reparse point
    if ($dirInfo.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
        return $result
    }

    try {
        $queue = [System.Collections.Generic.Queue[System.IO.DirectoryInfo]]::new()
        $queue.Enqueue($dirInfo)

        while ($queue.Count -gt 0) {
            $current = $queue.Dequeue()

            try {
                foreach ($entry in $current.EnumerateFileSystemInfos()) {
                    # Skip reparse points
                    if ($entry.Attributes.HasFlag([System.IO.FileAttributes]::ReparsePoint)) {
                        continue
                    }

                    if ($entry -is [System.IO.DirectoryInfo]) {
                        $queue.Enqueue($entry)
                    }
                    else {
                        # Skip cloud placeholders
                        if (Test-IsCloudPlaceholder -Item $entry) { continue }

                        $result.FileCount++
                        try { $result.TotalBytes += $entry.Length } catch { $null = $_ }
                    }
                }
            }
            catch [System.UnauthorizedAccessException] {
                # Access denied to this subdirectory -- skip
                $null = $_
            }
            catch [System.IO.PathTooLongException] {
                $null = $_
            }
            catch [System.IO.DirectoryNotFoundException] {
                # Disappeared between queue and enumerate -- race condition
                $null = $_
            }
            catch {
                $null = $_
            }
        }
    }
    catch {
        $null = $_
    }

    return $result
}

function Test-BrowserRunning {
    <#
    .SYNOPSIS
        Checks if a browser process is currently running.
    .DESCRIPTION
        Maps browser names to their process names and checks for running
        instances. Used to warn users before attempting cache deletion.
    .PARAMETER BrowserName
        The browser name (Chrome, Edge, Firefox, Brave, Opera, Arc, etc.).
    .OUTPUTS
        [bool] $true if the browser is running.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BrowserName
    )

    $processNames = switch -Wildcard ($BrowserName) {
        'Chrome'   { @('chrome') }
        'Edge'     { @('msedge') }
        'Firefox'  { @('firefox') }
        'Brave'    { @('brave') }
        'Opera*'   { @('opera') }
        'Arc'      { @('Arc') }
        'Vivaldi'  { @('vivaldi') }
        default    { @() }
    }

    foreach ($proc in $processNames) {
        if (Get-Process -Name $proc -ErrorAction SilentlyContinue) {
            return $true
        }
    }
    return $false
}

function Invoke-Cleanup {
    <#
    .SYNOPSIS
        Deletes files from selected cleanup targets.
    .DESCRIPTION
        Executes cleanup only on user-selected targets using SafeFileOps
        exclusively for all file operations. Creates a pre-deletion manifest,
        stops/starts wuauserv for WU cache cleanup, checks for running
        browsers, and reports total space recovered. Supports application-level
        WhatIf (never delegates to PS -WhatIf).
    .PARAMETER Targets
        Array of target objects (from Get-CleanupTargets) to clean.
    .PARAMETER WhatIf
        Preview mode -- show what would be deleted without deleting.
    .OUTPUTS
        [PSCustomObject] Summary with TotalFiles, TotalBytes, SkippedFiles, Errors.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'WhatIf used in conditional branches')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Application-level WhatIf -- intentionally not using ShouldProcess')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [array]$Targets,

        [switch]$WhatIf
    )

    $summary = [PSCustomObject]@{
        TotalFiles   = 0
        TotalBytes   = [long]0
        SkippedFiles = 0
        Errors       = 0
    }

    if ($Targets.Count -eq 0) {
        Write-Info 'No targets selected for cleanup.'
        return $summary
    }

    # Calculate total estimated size for anomaly detection
    $estimatedBytes = [long]0
    foreach ($t in $Targets) { $estimatedBytes += $t.Size }

    # Create pre-deletion manifest (HB-4)
    if (-not $WhatIf) {
        $manifestPath = New-CleanupManifest -Targets $Targets -TotalBytes $estimatedBytes
        Write-Info "Cleanup manifest saved to: $manifestPath"
    }

    # Check for running browsers before cleaning browser caches
    $browserTargets = @($Targets | Where-Object { $_.Type -eq 'browser' })
    $runningBrowsers = @{}
    foreach ($bt in $browserTargets) {
        $browserName = ($bt.Name -replace ' Cache.*$', '')
        if (-not $runningBrowsers.ContainsKey($browserName)) {
            if (Test-BrowserRunning -BrowserName $browserName) {
                $runningBrowsers[$browserName] = $true
                Write-Warn "Close $browserName before cleaning its cache for best results."
            }
        }
    }

    # Process each target
    $wuServiceStopped = $false

    foreach ($target in $Targets) {
        if ($WhatIf) {
            Write-Info "WhatIf: Would clean $($target.Name) ($($target.FileCount) files, $(Format-FileSize -Bytes $target.Size))"
            $summary.TotalFiles += $target.FileCount
            $summary.TotalBytes += $target.Size
            continue
        }

        Write-Info "Cleaning: $($target.Name)..."

        # Stop Windows Update service before cleaning WU cache
        if ($target.Type -eq 'wucache' -and -not $wuServiceStopped) {
            try {
                $wuSvc = Get-Service -Name wuauserv -ErrorAction SilentlyContinue
                if ($wuSvc -and $wuSvc.Status -eq 'Running') {
                    Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
                    $wuServiceStopped = $true
                    Write-Info 'Stopped Windows Update service for cache cleanup.'
                }
            }
            catch {
                Write-Warn "Could not stop Windows Update service: $($_.Exception.Message)"
            }
        }

        # Use SafeFileOps for deletion
        $result = Remove-SafeDirectory -Path $target.Path -WhatIf:$WhatIf
        $summary.TotalFiles   += $result.DeletedFiles
        $summary.TotalBytes   += $result.DeletedBytes
        $summary.SkippedFiles += $result.SkippedFiles
        $summary.Errors       += $result.Errors

        Write-Success "$($target.Name): $(Format-FileSize -Bytes $result.DeletedBytes) recovered ($($result.DeletedFiles) files)"
    }

    # Restart Windows Update service if we stopped it
    if ($wuServiceStopped) {
        try {
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            Write-Info 'Restarted Windows Update service.'
        }
        catch {
            Write-Warn "Could not restart Windows Update service: $($_.Exception.Message)"
        }
    }

    # Anomaly detection (HB-4): warn if actual > estimate by >20%
    if (-not $WhatIf -and $estimatedBytes -gt 0) {
        $ratio = $summary.TotalBytes / $estimatedBytes
        if ($ratio -gt 1.2) {
            Write-Warn "Anomaly detected: deleted $(Format-FileSize -Bytes $summary.TotalBytes) but scan estimated $(Format-FileSize -Bytes $estimatedBytes). This may indicate filesystem changes during cleanup."
            Write-Log "ANOMALY: Deleted $($summary.TotalBytes) bytes vs estimated $estimatedBytes bytes (ratio: $([math]::Round($ratio, 2)))"
        }
    }

    if ($WhatIf) {
        Write-Info "WhatIf summary: Would recover $(Format-FileSize -Bytes $summary.TotalBytes) from $($summary.TotalFiles) files."
    }
    else {
        Write-Success "Total recovered: $(Format-FileSize -Bytes $summary.TotalBytes) from $($summary.TotalFiles) files."
        if ($summary.SkippedFiles -gt 0) {
            Write-Info "$($summary.SkippedFiles) file(s) skipped (locked, protected, or cloud placeholders)."
        }
        if ($summary.Errors -gt 0) {
            Write-Warn "$($summary.Errors) error(s) encountered. See log for details."
        }
    }

    return $summary
}
