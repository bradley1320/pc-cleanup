# ==============================================================================
# PC Cleanup v2 -- 03-SafetyNet.ps1
# Safety layers: System Restore Points, registry backups
# Called automatically before the first modification in any session
# ==============================================================================

function New-SafetyRestorePoint {
    <#
    .SYNOPSIS
        Creates a System Restore Point with duplicate prevention.
    .DESCRIPTION
        Creates a restore point with a 24-hour duplicate check to avoid
        flooding the restore point list. Uses a 20-second timeout to prevent
        hanging. If System Restore is disabled (by policy, low disk, or user),
        logs a warning and continues -- does NOT abort. Falls back to registry
        backup as primary safety net.
    .OUTPUTS
        [bool] $true if created successfully, $false if skipped/failed.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not (Test-IsAdmin)) {
        Write-Warn 'System Restore Point requires administrator privileges -- skipping.'
        return $false
    }

    try {
        # Check if System Restore is enabled
        $srEnabled = $true
        try {
            $srConfig = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' -Name 'RPSessionInterval' -ErrorAction SilentlyContinue
            if ($null -ne $srConfig -and $srConfig.RPSessionInterval -eq 0) {
                $srEnabled = $false
            }
        }
        catch {
            # Can't determine -- try anyway
            $null = $_
        }

        if (-not $srEnabled) {
            Write-Warn 'System Restore is disabled on this machine. Registry backup will be used as primary safety net.'
            return $false
        }

        # 24hr duplicate check -- avoid flooding restore points
        try {
            $recentPoints = Get-ComputerRestorePoint -ErrorAction SilentlyContinue |
                Where-Object { $_.Description -like '*PCCleanup*' } |
                Where-Object {
                    # CreationTime comes as a WMI datetime string -- parse it
                    $created = [System.Management.ManagementDateTimeConverter]::ToDateTime($_.CreationTime)
                    $created -gt (Get-Date).AddHours(-24)
                }
            if ($recentPoints) {
                Write-Info 'A PCCleanup restore point was created within the last 24 hours -- skipping duplicate.'
                return $true
            }
        }
        catch {
            # Can't check -- proceed to create
            $null = $_
        }

        # Create with timeout using a background job
        Write-Info 'Creating System Restore Point...'
        $job = Start-Job -ScriptBlock {
            Checkpoint-Computer -Description 'PCCleanup Safety Point' -RestorePointType MODIFY_SETTINGS
        }
        $completed = Wait-Job $job -Timeout 20

        if ($null -eq $completed -or $job.State -ne 'Completed') {
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -Force -ErrorAction SilentlyContinue
            Write-Warn 'System Restore Point creation timed out. Registry backup will be used as primary safety net.'
            return $false
        }

        # Check for errors in the job
        $jobError = $job.ChildJobs[0].Error
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        if ($jobError -and $jobError.Count -gt 0) {
            Write-Warn "System Restore Point could not be created: $($jobError[0]). Registry backup will be used as primary safety net."
            return $false
        }

        Write-Success 'System Restore Point created successfully.'
        return $true
    }
    catch {
        Write-Warn "System Restore Point could not be created: $($_.Exception.Message). Registry backup will be used as primary safety net."
        return $false
    }
}

function Backup-RegistryHive {
    <#
    .SYNOPSIS
        Exports a registry key to a timestamped .reg file.
    .DESCRIPTION
        Uses reg.exe export to create a backup of the specified registry
        path. Stored in the backups directory with timestamps for recovery.
    .PARAMETER Path
        The registry hive/path to back up (e.g. 'HKLM:\SOFTWARE\Policies').
    .PARAMETER OutputDir
        The directory to save the backup file to.
    .OUTPUTS
        [string] Path to the created backup file, or $null on failure.
    .EXAMPLE
        Backup-RegistryHive -Path 'HKLM:\SOFTWARE\Policies' -OutputDir "$env:LOCALAPPDATA\PCCleanup\backups"
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Params used in expressions and string interpolation')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$OutputDir
    )

    try {
        if (-not (Test-Path $OutputDir)) {
            New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
        }

        # Build safe filename from the registry path
        $safeName = $Path -replace '[:\\]', '_'
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $fileName = "PCCleanup_${safeName}_${timestamp}.reg"
        $outputFile = Join-Path $OutputDir $fileName

        # Convert PowerShell path to reg.exe format (HKLM: --> HKLM\, HKCU: --> HKCU\)
        $regPath = $Path -replace ':', ''

        $result = reg.exe export $regPath $outputFile /y 2>&1

        if (Test-Path $outputFile) {
            Write-Success "Registry backup saved: $fileName"
            Write-Log "SafetyNet: Registry backup exported '$Path' to '$outputFile'"
            return $outputFile
        }
        else {
            Write-Warn "Registry backup may have failed for '$Path': $result"
            return $null
        }
    }
    catch {
        Write-Err -Message "Failed to back up registry hive '$Path'" -Cause $_.Exception.Message -Fix 'Run as Administrator, or check that the registry path is valid.'
        return $null
    }
}

function Get-SafetyStatus {
    <#
    .SYNOPSIS
        Returns a summary of available safety nets.
    .DESCRIPTION
        Reports on available restore points, registry backups, and
        undo log status. Used for user-facing safety status display.
    .OUTPUTS
        [PSCustomObject] Summary with RestorePoints, Backups, and UndoLogEntries properties.
    #>
    [CmdletBinding()]
    param()

    $restorePointCount = 0
    try {
        $points = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
        if ($points) {
            $restorePointCount = @($points).Count
        }
    }
    catch {
        # Can't query restore points -- leave at 0
        $null = $_
    }

    $backupCount = 0
    $backupDir = Join-Path $env:LOCALAPPDATA 'PCCleanup\backups'
    if (Test-Path $backupDir) {
        $regFiles = Get-ChildItem -Path $backupDir -Filter '*.reg' -ErrorAction SilentlyContinue
        if ($regFiles) {
            $backupCount = @($regFiles).Count
        }
    }

    $undoCount = 0
    $undoLogPath = Join-Path $env:LOCALAPPDATA 'PCCleanup\undo_log.json'
    if (Test-Path $undoLogPath) {
        try {
            $undoData = Get-Content -Path $undoLogPath -Raw | ConvertFrom-Json
            if ($undoData) {
                $undoCount = @($undoData).Count
            }
        }
        catch {
            # Corrupted log -- leave at 0
            $null = $_
        }
    }

    return [PSCustomObject]@{
        RestorePoints  = $restorePointCount
        Backups        = $backupCount
        UndoLogEntries = $undoCount
    }
}
