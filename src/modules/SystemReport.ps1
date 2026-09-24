# ==============================================================================
# PC Cleanup v2 -- SystemReport.ps1
# Before/after metrics collection and comparison.
# Boot timing comes only from Event ID 100 -- see Get-BootTimeMeasurement.
# ==============================================================================

$script:SnapshotDir = Join-Path $env:LOCALAPPDATA 'PCCleanup\snapshots'

function Get-SystemSnapshot {
    <#
    .SYNOPSIS
        Collects a point-in-time system metrics snapshot.
    .DESCRIPTION
        Captures boot time (Event ID 100 from the Diagnostics-Performance log,
        or -1 when that cannot be read), process count, free disk space, and
        startup program count.
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
    Write-Info "Boot time: $(Format-BootTime -BootTimeMs $snapshot.BootTimeMs -Source $snapshot.BootTimeSource)"
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
        formatted comparison table. Boot time is compared only when both
        snapshots measured it from Event ID 100.
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

    # Boot time is only comparable when both snapshots actually measured it.
    # Snapshots saved by v2.0.0 hold uptime under the 'CIM' source, and a delta
    # against uptime reports a speed-up or slow-down that never happened.
    if ($before.BootTimeSource -eq 'EventID100' -and $after.BootTimeSource -eq 'EventID100') {
        Show-MetricDelta -Label 'Boot Time' -Before $before.BootTimeMs -After $after.BootTimeMs -Unit 'ms' -LowerIsBetter $true
    }
    else {
        Write-Host ("  {0,-20}not compared" -f 'Boot Time') -ForegroundColor Yellow
        Write-Host "    Before: $(Format-BootTime -BootTimeMs $before.BootTimeMs -Source $before.BootTimeSource)" -ForegroundColor Yellow
        Write-Host "    After:  $(Format-BootTime -BootTimeMs $after.BootTimeMs -Source $after.BootTimeSource)" -ForegroundColor Yellow
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

function Format-BootTime {
    <#
    .SYNOPSIS
        Formats a snapshot's boot time for display.
    .DESCRIPTION
        Shows the measured duration with its source, or says plainly that there
        is no measurement instead of printing the -1 sentinel. Snapshots saved
        by v2.0.0 carry the 'CIM' source, whose value was uptime, not boot time.
    .PARAMETER BootTimeMs
        The BootTimeMs value from a snapshot.
    .PARAMETER Source
        The BootTimeSource value from a snapshot.
    .EXAMPLE
        Format-BootTime -BootTimeMs 76919 -Source 'EventID100'
    #>
    [CmdletBinding()]
    param(
        [long]$BootTimeMs,
        [string]$Source
    )

    if ($Source -eq 'EventID100' -and $BootTimeMs -ge 0) {
        "${BootTimeMs}ms (source: Event ID 100)"
    }
    elseif ($Source -eq 'CIM') {
        'not measured (saved by v2.0.0, which recorded uptime instead of boot time)'
    }
    else {
        'not available (Windows boot diagnostics, Event ID 100, could not be read)'
    }
}

# --- Internal helper functions ---

function Get-BootTimeMeasurement {
    <#
    .SYNOPSIS
        Measures the last boot's duration from Event ID 100.
    .DESCRIPTION
        Reads the newest Event ID 100 from the
        Microsoft-Windows-Diagnostics-Performance/Operational log and returns
        MainPathBootTime + BootPostBootTime, which Windows itself reports as the
        boot duration. Fields are read by name from the event XML. Reading them
        by position is what broke v2.0.0: the event carries 40+ fields and the
        first two are a version number and a start timestamp, so the cast threw
        on every real machine.

        When the event cannot be read this returns -1 with source 'Unavailable'.
        There is deliberately no fallback. CIM_OperatingSystem.LastBootUpTime
        says when Windows started, not how long starting took, and the uptime it
        yields made before/after comparisons show speed-ups that never happened.
    .OUTPUTS
        [PSCustomObject] With BootTimeMs and Source properties.
    #>
    [CmdletBinding()]
    param()

    try {
        $logName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
        $bootEvent = Get-WinEvent -LogName $logName -FilterXPath "*[System[EventID=100]]" -MaxEvents 1 -ErrorAction Stop

        $fields = @{}
        foreach ($data in ([xml]$bootEvent.ToXml()).Event.EventData.Data) {
            $fields[$data.Name] = $data.'#text'
        }

        [long]$mainPathMs = 0
        [long]$postBootMs = 0
        if ([long]::TryParse($fields['MainPathBootTime'], [ref]$mainPathMs) -and
            [long]::TryParse($fields['BootPostBootTime'], [ref]$postBootMs) -and
            $mainPathMs -gt 0) {
            return [PSCustomObject]@{
                BootTimeMs = $mainPathMs + $postBootMs
                Source     = 'EventID100'
            }
        }
        Write-Verbose 'Event ID 100 has no usable MainPathBootTime/BootPostBootTime fields.'
    }
    catch {
        # No event yet, log disabled, or access denied -- all mean "not measured".
        Write-Verbose "Event ID 100 unavailable: $($_.Exception.Message)"
    }

    [PSCustomObject]@{
        BootTimeMs = -1
        Source     = 'Unavailable'
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
