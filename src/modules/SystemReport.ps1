# ==============================================================================
# PC Cleanup v2 -- SystemReport.ps1
# Before/after metrics collection and comparison.
# Uses Event ID 100 for boot timing with CIM fallback.
# ==============================================================================

$script:SnapshotDir = Join-Path $env:LOCALAPPDATA 'PCCleanup\snapshots'

function Get-SystemSnapshot {
    <#
    .SYNOPSIS
        Collects a point-in-time system metrics snapshot.
    .DESCRIPTION
        Captures boot time (Event ID 100 from Diagnostics-Performance log,
        with CIM_OperatingSystem fallback), process count, free disk space,
        and startup program count.
    .OUTPUTS
        [PSCustomObject] Snapshot with BootTimeMs, BootTimeSource, ProcessCount,
        FreeDiskBytes, StartupCount, and CapturedAt.
    #>
    [CmdletBinding()]
    param()

    # Boot time measurement
    $bootInfo = Get-BootTimeMeasurement

    # Process count
    $processCount = @(Get-Process).Count

    # Free disk space on system drive
    $freeDiskBytes = 0
    try {
        $systemDrive = $env:SystemDrive
        if ($systemDrive) {
            $driveLetter = $systemDrive.TrimEnd(':')
            $driveInfo = [System.IO.DriveInfo]::new("${driveLetter}:")
            $freeDiskBytes = $driveInfo.AvailableFreeSpace
        }
    }
    catch {
        $null = $_
    }

    # Startup program count (safe call -- may not be loaded in all contexts)
    $startupCount = 0
    try {
        $regPaths = @(
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        )
        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                $key = Get-Item -LiteralPath $regPath -ErrorAction SilentlyContinue
                if ($key) { $startupCount += $key.GetValueNames().Count }
            }
        }
    }
    catch {
        $null = $_
    }

    return [PSCustomObject]@{
        BootTimeMs     = $bootInfo.BootTimeMs
        BootTimeSource = $bootInfo.Source
        ProcessCount   = $processCount
        FreeDiskBytes  = $freeDiskBytes
        StartupCount   = $startupCount
        CapturedAt     = (Get-Date).ToString('o')
    }
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
    .EXAMPLE
        Save-SystemSnapshot -Label 'Before'
        Save-SystemSnapshot -Label 'After'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Label
    )

    $snapshot = Get-SystemSnapshot

    if (-not (Test-Path $script:SnapshotDir)) {
        New-Item -ItemType Directory -Path $script:SnapshotDir -Force | Out-Null
    }

    $safeLabel = $Label -replace '[^\w\-]', '_'
    $fileName = "snapshot_${safeLabel}_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $filePath = Join-Path $script:SnapshotDir $fileName

    $snapshot | ConvertTo-Json -Depth 5 | Set-Content -Path $filePath -Encoding UTF8

    Write-Success "Snapshot '$Label' saved to $filePath"
    Write-Info "Boot time: $($snapshot.BootTimeMs)ms (source: $($snapshot.BootTimeSource))"
    Write-Info "Processes: $($snapshot.ProcessCount) | Free disk: $(Format-FileSize $snapshot.FreeDiskBytes) | Startup items: $($snapshot.StartupCount)"

    return $snapshot
}

function Compare-Snapshots {
    <#
    .SYNOPSIS
        Compares before and after snapshots and displays deltas.
    .DESCRIPTION
        Loads the most recent 'Before' and 'After' snapshots from the
        snapshot directory. Calculates differences and displays a
        formatted comparison table. Notes data source differences
        (Event ID 100 vs WMI) in the output.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Compares multiple snapshots')]
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:SnapshotDir)) {
        Write-Warn 'No snapshots found. Use Save-SystemSnapshot to capture before/after data.'
        return
    }

    $files = Get-ChildItem -Path $script:SnapshotDir -Filter 'snapshot_*.json' -File | Sort-Object LastWriteTime

    if ($files.Count -lt 2) {
        Write-Warn "Need at least 2 snapshots to compare. Found $($files.Count)."
        Write-Info 'Run Save-SystemSnapshot -Label "Before" and Save-SystemSnapshot -Label "After".'
        return
    }

    # Load the two most recent snapshots
    $beforeFile = $files | Where-Object { $_.Name -match 'Before' } | Select-Object -Last 1
    $afterFile = $files | Where-Object { $_.Name -match 'After' } | Select-Object -Last 1

    # If no Before/After labels, use first and last files
    if ($null -eq $beforeFile) { $beforeFile = $files[0] }
    if ($null -eq $afterFile) { $afterFile = $files[-1] }

    if ($beforeFile.FullName -eq $afterFile.FullName) {
        Write-Warn 'Only one unique snapshot found. Need both a Before and After snapshot.'
        return
    }

    $before = Get-Content -Path $beforeFile.FullName -Raw | ConvertFrom-Json
    $after = Get-Content -Path $afterFile.FullName -Raw | ConvertFrom-Json

    # Display comparison
    Write-Host ""
    Write-Host "  =================================" -ForegroundColor White
    Write-Host "      SYSTEM METRICS COMPARISON     " -ForegroundColor White
    Write-Host "  =================================" -ForegroundColor White
    Write-Host ""
    Write-Host "  Before: $($beforeFile.Name)" -ForegroundColor DarkGray
    Write-Host "  After:  $($afterFile.Name)" -ForegroundColor DarkGray
    Write-Host ""

    # Boot time comparison
    Show-MetricDelta -Label 'Boot Time' -Before $before.BootTimeMs -After $after.BootTimeMs -Unit 'ms' -LowerIsBetter $true

    # Boot time source note
    if ($before.BootTimeSource -ne $after.BootTimeSource) {
        Write-Host "    Note: Boot time sources differ -- Before: $($before.BootTimeSource), After: $($after.BootTimeSource)" -ForegroundColor Yellow
        if ($after.BootTimeSource -eq 'CIM') {
            Write-Host "    (CIM/WMI is less granular -- diagnostic logging may be disabled by privacy tweaks)" -ForegroundColor Yellow
        }
    }

    # Process count
    Show-MetricDelta -Label 'Process Count' -Before $before.ProcessCount -After $after.ProcessCount -Unit '' -LowerIsBetter $true

    # Free disk space (higher is better)
    $beforeDiskMB = [math]::Round($before.FreeDiskBytes / 1MB, 0)
    $afterDiskMB = [math]::Round($after.FreeDiskBytes / 1MB, 0)
    Show-MetricDelta -Label 'Free Disk Space' -Before $beforeDiskMB -After $afterDiskMB -Unit 'MB' -LowerIsBetter $false

    # Startup count
    Show-MetricDelta -Label 'Startup Items' -Before $before.StartupCount -After $after.StartupCount -Unit '' -LowerIsBetter $true

    Write-Host ""
    Write-Info 'Tip: First reboot after changes may be slower. Restart twice before taking the "After" snapshot for accurate boot time comparison.'
    Write-Host ""

    return [PSCustomObject]@{
        Before = $before
        After  = $after
    }
}

# --- Internal helper functions ---

function Get-BootTimeMeasurement {
    <#
    .SYNOPSIS
        Measures boot time using Event ID 100, with CIM fallback.
    .DESCRIPTION
        Uses Microsoft-Windows-Diagnostics-Performance/Operational Event ID 100
        for accurate phase-by-phase boot timing (MainPathBootTime + BootPostBootTime).
        Falls back to LastBootUpTime from CIM_OperatingSystem if event log
        is unavailable (privacy tweaks may disable diagnostic performance logging).
    .OUTPUTS
        [PSCustomObject] With BootTimeMs and Source properties.
    #>
    [CmdletBinding()]
    param()

    # Try Event ID 100 first (most accurate)
    try {
        $logName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
        $bootEvent = Get-WinEvent -LogName $logName -FilterXPath "*[System[EventID=100]]" -MaxEvents 1 -ErrorAction Stop

        if ($bootEvent -and $bootEvent.Properties.Count -ge 2) {
            # Property 0 = MainPathBootTime (ms), Property 1 = BootPostBootTime (ms)
            $mainPathMs = [long]$bootEvent.Properties[0].Value
            $postBootMs = [long]$bootEvent.Properties[1].Value
            $totalMs = $mainPathMs + $postBootMs

            return [PSCustomObject]@{
                BootTimeMs = $totalMs
                Source     = 'EventID100'
            }
        }
    }
    catch {
        # Event log unavailable -- fallback to CIM
        $null = $_
    }

    # CIM fallback: time since last boot
    try {
        $os = Get-CimInstance -ClassName CIM_OperatingSystem -ErrorAction Stop
        $uptime = (Get-Date) - $os.LastBootUpTime
        $uptimeMs = [long]$uptime.TotalMilliseconds

        return [PSCustomObject]@{
            BootTimeMs = $uptimeMs
            Source     = 'CIM'
        }
    }
    catch {
        return [PSCustomObject]@{
            BootTimeMs = -1
            Source     = 'Unavailable'
        }
    }
}

function Show-MetricDelta {
    <#
    .SYNOPSIS
        Displays a single metric comparison with colored delta.
    .PARAMETER Label
        The metric name.
    .PARAMETER Before
        The before value.
    .PARAMETER After
        The after value.
    .PARAMETER Unit
        The unit suffix (e.g. 'ms', 'MB', '').
    .PARAMETER LowerIsBetter
        If true, a decrease is shown in green. If false, an increase is green.
    #>
    [CmdletBinding()]
    param(
        [string]$Label,
        [long]$Before,
        [long]$After,
        [string]$Unit,
        [bool]$LowerIsBetter = $true
    )

    $delta = $After - $Before
    $deltaSign = if ($delta -gt 0) { '+' } elseif ($delta -lt 0) { '' } else { '' }
    $deltaStr = "${deltaSign}${delta}"

    $isImproved = if ($LowerIsBetter) { $delta -lt 0 } else { $delta -gt 0 }
    $isWorse = if ($LowerIsBetter) { $delta -gt 0 } else { $delta -lt 0 }
    $deltaColor = if ($isImproved) { 'Green' } elseif ($isWorse) { 'Red' } else { 'DarkGray' }

    $pad = ' ' * [math]::Max(0, 20 - $Label.Length)
    Write-Host "  $Label${pad}Before: $Before $Unit  |  After: $After $Unit  |  " -NoNewline
    Write-Host "$deltaStr $Unit" -ForegroundColor $deltaColor
}
