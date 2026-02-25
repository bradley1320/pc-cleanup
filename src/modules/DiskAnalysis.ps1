# ==============================================================================
# PC Cleanup v2 -- DiskAnalysis.ps1
# Disk usage visualization and folder size analysis. Completely read-only.
# ==============================================================================

function Get-DriveUsage {
    <#
    .SYNOPSIS
        Displays drive usage bars with color coding.
    .DESCRIPTION
        Shows each fixed drive's total, used, and free space with a visual bar.
        Color coded: green (<70%), yellow (70-90%), red (>90%).
    .OUTPUTS
        [PSCustomObject[]] Array of drive usage objects.
    .EXAMPLE
        Get-DriveUsage
    #>
    [CmdletBinding()]
    param()

    $drives = @()

    try {
        $driveInfos = [System.IO.DriveInfo]::GetDrives() | Where-Object {
            $_.DriveType -eq 'Fixed' -and $_.IsReady
        }
    }
    catch {
        Write-Err -Message 'Could not enumerate drives' -Cause $_.Exception.Message -Fix 'Check that drive letters are accessible.'
        return $drives
    }

    foreach ($driveInfo in $driveInfos) {
        try {
            $total = $driveInfo.TotalSize
            $free = $driveInfo.AvailableFreeSpace
            $used = $total - $free
            $pctUsed = if ($total -gt 0) { [math]::Round(($used / $total) * 100, 1) } else { 0 }

            $drives += [PSCustomObject]@{
                Drive      = $driveInfo.Name.TrimEnd('\')
                Label      = $driveInfo.VolumeLabel
                TotalBytes = $total
                UsedBytes  = $used
                FreeBytes  = $free
                PctUsed    = $pctUsed
            }
        }
        catch {
            $null = $_
        }
    }

    return $drives
}

function Show-DriveUsage {
    <#
    .SYNOPSIS
        Displays formatted drive usage bars to the console.
    .DESCRIPTION
        Calls Get-DriveUsage and renders each drive as a colored bar chart.
        Green (<70%), Yellow (70-90%), Red (>90%).
    #>
    [CmdletBinding()]
    param()

    $drives = Get-DriveUsage

    if ($drives.Count -eq 0) {
        Write-Info 'No fixed drives detected.'
        return
    }

    Write-Host ""
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host "         DRIVE USAGE             " -ForegroundColor White
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host ""

    foreach ($drive in $drives) {
        $color = if ($drive.PctUsed -lt 70) { 'Green' }
                 elseif ($drive.PctUsed -lt 90) { 'Yellow' }
                 else { 'Red' }

        $barWidth = 30
        $filledWidth = [math]::Round(($drive.PctUsed / 100) * $barWidth)
        $emptyWidth = $barWidth - $filledWidth
        $bar = ('=' * $filledWidth) + (' ' * $emptyWidth)

        $label = if ($drive.Label) { "$($drive.Drive) ($($drive.Label))" } else { $drive.Drive }
        $pad = ' ' * [math]::Max(0, 20 - $label.Length)

        Write-Host "  $label$pad[" -NoNewline
        Write-Host $bar -ForegroundColor $color -NoNewline
        Write-Host "] $($drive.PctUsed)%"
        Write-Host "  $((' ' * 20))$(Format-FileSize $drive.UsedBytes) used / $(Format-FileSize $drive.TotalBytes) total ($(Format-FileSize $drive.FreeBytes) free)"
        Write-Host ""
    }
}

function Get-FolderSizes {
    <#
    .SYNOPSIS
        Recursively analyzes folder sizes.
    .DESCRIPTION
        Scans a directory tree to the specified depth, reporting size of
        each folder. Uses queue-based BFS to avoid deep recursion.
        Skips reparse points (junctions/symlinks) for safety.
    .PARAMETER Path
        The root path to analyze.
    .PARAMETER Depth
        How many levels deep to scan (default: 3).
    .OUTPUTS
        [PSCustomObject[]] Array of folder objects with Path, Size, and FileCount.
    .EXAMPLE
        Get-FolderSizes -Path 'C:\Users' -Depth 2
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [int]$Depth = 3
    )

    $results = @()

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warn "Path not found: $Path"
        return $results
    }

    try {
        $children = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) }
    }
    catch {
        Write-Warn "Cannot read directory: $Path"
        return $results
    }

    foreach ($child in $children) {
        try {
            $size = [long]0
            $fileCount = 0

            # Queue-based BFS for size calculation (respects depth, skips reparse points)
            $queue = [System.Collections.Queue]::new()
            $queue.Enqueue(@{ Dir = $child.FullName; Level = 0 })

            while ($queue.Count -gt 0) {
                $item = $queue.Dequeue()
                $dir = $item.Dir
                $level = $item.Level

                try {
                    $dirInfo = [System.IO.DirectoryInfo]::new($dir)

                    foreach ($file in $dirInfo.EnumerateFiles()) {
                        try {
                            $size += $file.Length
                            $fileCount++
                        }
                        catch {
                            $null = $_
                        }
                    }

                    if ($level -lt $Depth) {
                        foreach ($subDir in $dirInfo.EnumerateDirectories()) {
                            # Skip reparse points
                            if ($subDir.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                            $queue.Enqueue(@{ Dir = $subDir.FullName; Level = ($level + 1) })
                        }
                    }
                }
                catch {
                    $null = $_
                }
            }

            $results += [PSCustomObject]@{
                Path      = $child.FullName
                Name      = $child.Name
                Size      = $size
                FileCount = $fileCount
            }
        }
        catch {
            $null = $_
        }
    }

    # Sort by size descending
    $results = @($results | Sort-Object -Property Size -Descending)

    return $results
}

function Show-FolderSizes {
    <#
    .SYNOPSIS
        Displays formatted folder size analysis.
    .DESCRIPTION
        Scans the specified directory and shows a table of subdirectory sizes,
        sorted from largest to smallest.
    .PARAMETER Path
        The root path to analyze. Default: system drive root.
    .PARAMETER Depth
        How many levels deep to scan. Default: 3.
    #>
    [CmdletBinding()]
    param(
        [string]$Path,

        [int]$Depth = 3
    )

    if (-not $Path) {
        $Path = $env:SystemDrive + '\'
    }

    Write-Info "Analyzing folder sizes in $Path (depth: $Depth)..."
    Write-Info 'This may take a moment for large directories.'
    Write-Host ""

    $folders = Get-FolderSizes -Path $Path -Depth $Depth

    if ($folders.Count -eq 0) {
        Write-Info 'No accessible subdirectories found.'
        return
    }

    # Display top folders
    $maxDisplay = [math]::Min($folders.Count, 20)
    Write-Host "  Top $maxDisplay folders by size:" -ForegroundColor White
    Write-Host ""

    for ($i = 0; $i -lt $maxDisplay; $i++) {
        $folder = $folders[$i]
        $sizeStr = Format-FileSize $folder.Size
        $pad = ' ' * [math]::Max(0, 12 - $sizeStr.Length)
        Write-Host "  $pad$sizeStr  $($folder.Name) ($($folder.FileCount) files)"
    }

    Write-Host ""
}

function Show-DiskAnalysisMenu {
    <#
    .SYNOPSIS
        Interactive menu for disk analysis operations.
    .DESCRIPTION
        Completely read-only. Provides drive usage overview and
        folder size analysis for any directory.
    #>
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host "         DISK ANALYSIS           " -ForegroundColor White
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host ""
    Write-Host "  1. Drive Usage Overview"
    Write-Host "  2. Folder Size Analysis (System Drive)"
    Write-Host "  3. Folder Size Analysis (Custom Path)"
    Write-Host ""
    Write-Host "  [B] Back"
    Write-Host ""

    try {
        $choice = Read-Host '  Choice'
    }
    catch {
        return
    }

    if ([string]::IsNullOrWhiteSpace($choice)) { return }
    $choice = $choice.Trim()

    if ($choice -eq 'B' -or $choice -eq 'b') { return }

    switch ($choice) {
        '1' {
            Show-DriveUsage
        }
        '2' {
            Show-FolderSizes
        }
        '3' {
            try {
                $customPath = Read-Host '  Enter path to analyze'
            }
            catch {
                return
            }
            if (-not [string]::IsNullOrWhiteSpace($customPath)) {
                Show-FolderSizes -Path $customPath.Trim()
            }
        }
        default {
            Write-Warn "Unrecognized input: $choice"
        }
    }
}
