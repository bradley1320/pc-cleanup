# ==============================================================================
# PC Cleanup v2 -- 05-UndoManager.ps1
# Tracks applied tweaks with full original state captured at apply time.
# Enables per-tweak and bulk undo. Persists to undo_log.json between sessions.
# ==============================================================================

# Undo log lives at %LOCALAPPDATA%\PCCleanup\undo_log.json
$script:UndoLogDir = Join-Path $env:LOCALAPPDATA 'PCCleanup'
$script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'

function Test-UndoLogEntry {
    <#
    .SYNOPSIS
        Validates the structure of a single undo log entry.
    .DESCRIPTION
        Checks that the entry has all required fields (TweakName, AppliedAt,
        Changes) and that each change record has a valid Type and the required
        fields for that type. Returns $false for malformed entries to prevent
        executing garbage data from a tampered or corrupted undo log.
    .PARAMETER Entry
        The undo log entry object to validate.
    .OUTPUTS
        [bool] $true if the entry is structurally valid, $false otherwise.
    #>
    [CmdletBinding()]
    param($Entry)

    if ($null -eq $Entry) { return $false }

    # Must have non-empty TweakName
    if ([string]::IsNullOrWhiteSpace($Entry.TweakName)) { return $false }

    # Must have AppliedAt
    if ([string]::IsNullOrWhiteSpace([string]$Entry.AppliedAt)) { return $false }

    # Must have Changes (non-null, at least one)
    if ($null -eq $Entry.Changes) { return $false }
    $changes = @($Entry.Changes)
    if ($changes.Count -eq 0) { return $false }

    # Validate each change has a recognized Type and required fields
    $validTypes = @('Registry', 'Service', 'ScheduledTask', 'Script', 'StartupRegistry', 'StartupFolder')
    foreach ($change in $changes) {
        $changeType = [string]$change.Type
        if ($changeType -notin $validTypes) { return $false }

        switch ($changeType) {
            'Registry' {
                if ([string]::IsNullOrWhiteSpace($change.Path)) { return $false }
                if ([string]::IsNullOrWhiteSpace($change.Name)) { return $false }
            }
            'Service' {
                if ([string]::IsNullOrWhiteSpace($change.Name)) { return $false }
            }
            'ScheduledTask' {
                if ([string]::IsNullOrWhiteSpace($change.Path)) { return $false }
            }
            'StartupRegistry' {
                if ([string]::IsNullOrWhiteSpace($change.Path)) { return $false }
                if ([string]::IsNullOrWhiteSpace($change.Name)) { return $false }
            }
            'StartupFolder' {
                if ([string]::IsNullOrWhiteSpace($change.FilePath)) { return $false }
            }
        }
    }

    return $true
}

function Register-AppliedTweak {
    <#
    .SYNOPSIS
        Records a tweak application with its original system state.
    .DESCRIPTION
        Captures the ACTUAL current system state (not hardcoded defaults)
        for each change and appends a full undo record to the log. This
        ensures correct undo even when the user had custom settings.
    .PARAMETER Name
        The TweakID that was applied.
    .PARAMETER Changes
        Array of change records, each containing Type (Registry/Service/
        ScheduledTask), the target path/name, and the original value.
    .PARAMETER Timestamp
        When the tweak was applied.
    .PARAMETER Category
        The tweak category (Privacy, Performance, etc.).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [array]$Changes,

        [datetime]$Timestamp = (Get-Date),

        [string]$Category
    )

    try {
        if (-not (Test-Path $script:UndoLogDir)) {
            New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        }

        # Load existing log or start fresh
        $log = @()
        if (Test-Path $script:UndoLogPath) {
            $raw = Get-Content -Path $script:UndoLogPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json
                # ConvertFrom-Json returns a single object if there's one entry -- normalize to array
                $log = @($parsed)
            }
        }

        $entry = [PSCustomObject]@{
            TweakName      = $Name
            AppliedAt      = $Timestamp.ToString('o')
            AppliedOnBuild = Get-OSBuild
            Category       = $Category
            Changes        = $Changes
        }

        $log += $entry
        # Atomic write: temp file then rename to prevent corruption on crash
        $tempPath = "$($script:UndoLogPath).tmp"
        $log | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath -Encoding UTF8
        Move-Item -Path $tempPath -Destination $script:UndoLogPath -Force

        Write-Log "UndoManager: Registered '$Name' with $($Changes.Count) change(s)"
    }
    catch {
        Write-Err -Message "Failed to register undo data for '$Name'" -Cause $_.Exception.Message -Fix 'Check write permissions to %LOCALAPPDATA%\PCCleanup.'
    }
}

function Get-AppliedTweaks {
    <#
    .SYNOPSIS
        Returns list of currently applied (undoable) tweaks.
    .DESCRIPTION
        Reads the undo log and returns metadata for each applied tweak
        including name, category, timestamp, and OS build at apply time.
    .OUTPUTS
        [PSCustomObject[]] Array of applied tweak records.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path $script:UndoLogPath)) {
        return @()
    }

    try {
        $raw = Get-Content -Path $script:UndoLogPath -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @()
        }
        $parsed = $raw | ConvertFrom-Json
        $entries = @($parsed)

        # Validate each entry -- skip malformed ones
        $valid = @()
        foreach ($entry in $entries) {
            if (Test-UndoLogEntry $entry) {
                $valid += $entry
            }
            else {
                $entryName = if ($entry.TweakName) { $entry.TweakName } else { '(unnamed)' }
                Write-Warn "Skipping malformed undo log entry: $entryName. Entry has invalid or missing fields."
            }
        }
        return $valid
    }
    catch {
        Write-Warn "Undo log is corrupted: $($_.Exception.Message). Consider using System Restore Point."
        return @()
    }
}

function Invoke-UndoTweak {
    <#
    .SYNOPSIS
        Undoes a single applied tweak using stored original values.
    .DESCRIPTION
        Reads the undo log entry for the specified tweak and restores
        each changed value to its original state. Warns if the OS build
        has changed since the tweak was applied.
    .PARAMETER Name
        The TweakID to undo.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $log = Get-AppliedTweaks
    $entry = $log | Where-Object { $_.TweakName -eq $Name } | Select-Object -Last 1

    if ($null -eq $entry) {
        Write-Warn "No undo data found for '$Name' -- it may not have been applied through PC Cleanup."
        return
    }

    # Defense in depth: validate entry structure before applying
    if (-not (Test-UndoLogEntry $entry)) {
        Write-Warn "Undo log entry for '$Name' is malformed or contains invalid data. Refusing to apply."
        Write-Warn 'Consider using System Restore Point to revert changes instead.'
        return
    }

    # Warn if OS build changed since apply
    $currentBuild = Get-OSBuild
    if ($entry.AppliedOnBuild -and $entry.AppliedOnBuild -ne $currentBuild) {
        Write-Warn "This tweak was applied on build $($entry.AppliedOnBuild). Current build is $currentBuild. Undo values may not match current OS defaults."
    }

    Write-Info "Undoing '$Name'..."

    # SECURITY (F24): Cross-reference undo log paths against tweak definitions
    # to prevent undo log tampering from injecting arbitrary registry writes.
    $tweaksPath = Join-Path $script:ConfigPath 'tweaks.json'
    $tweakDef = $null
    $canValidatePaths = $false
    if (Test-Path $tweaksPath) {
        $tweakDef = (Get-Content -Path $tweaksPath -Raw | ConvertFrom-Json).$Name
        if ($null -ne $tweakDef) { $canValidatePaths = $true }
    }

    foreach ($change in $entry.Changes) {
        try {
            $changeType = [string]$change.Type

            # Validate declarative change paths against tweak definition.
            # StartupRegistry/StartupFolder bypass this (they're from StartupManager, not tweaks.json).
            # Script type is already safe (reads commands from tweaks.json, not undo log).
            if ($canValidatePaths -and $changeType -notin @('Script', 'StartupRegistry', 'StartupFolder')) {
                $pathValid = $false
                if ($changeType -eq 'Registry') {
                    $pathValid = @($tweakDef.registry | Where-Object { $_.path -eq $change.Path -and $_.name -eq $change.Name }).Count -gt 0
                }
                elseif ($changeType -eq 'Service') {
                    $pathValid = @($tweakDef.services | Where-Object { $_.name -eq $change.Name }).Count -gt 0
                }
                elseif ($changeType -eq 'ScheduledTask') {
                    $pathValid = @($tweakDef.scheduledTasks | Where-Object { $_.path -eq $change.Path }).Count -gt 0
                }
                if (-not $pathValid) {
                    Write-Warn "SECURITY: Undo log contains path not in tweak definition for '$Name'. Skipping change ($changeType): $($change.Path)\$($change.Name)"
                    Write-Log "SECURITY: Blocked undo path mismatch -- TweakName=$Name Type=$changeType Path=$($change.Path) Name=$($change.Name)"
                    continue
                }
            }

            if ($changeType -eq 'Registry') {
                if ($change.KeyExistedBefore -eq $false) {
                    # Value didn't exist before -- remove it
                    Set-PCCleanupRegistry -Path $change.Path -Name $change.Name -Value '<RemoveEntry>' -Type 'DWord'
                }
                else {
                    Set-PCCleanupRegistry -Path $change.Path -Name $change.Name -Value $change.OriginalValue -Type $change.OriginalType
                }
            }
            elseif ($changeType -eq 'Service') {
                Set-PCCleanupService -Name $change.Name -StartupType $change.OriginalStartupType
                if ($change.OriginalStatus -eq 'Running') {
                    Start-Service -Name $change.Name -ErrorAction SilentlyContinue
                }
            }
            elseif ($changeType -eq 'ScheduledTask') {
                Set-PCCleanupScheduledTask -TaskPath $change.Path -Enabled $change.OriginalEnabled
            }
            elseif ($changeType -eq 'Script') {
                # SECURITY: Undo commands are read from tweaks.json (shipped config),
                # NOT from undo_log.json (user-writable). This prevents privilege
                # escalation via undo log tampering. $script:ConfigPath is set by
                # 04-TweakEngine.ps1 which loads before this module.
                $tweaksPath = Join-Path $script:ConfigPath 'tweaks.json'
                if (Test-Path $tweaksPath) {
                    $tweakDef = (Get-Content -Path $tweaksPath -Raw | ConvertFrom-Json).$($entry.TweakName)
                    if ($tweakDef -and $tweakDef.undoScript -and $tweakDef.undoScript.Count -gt 0) {
                        foreach ($cmd in $tweakDef.undoScript) {
                            Invoke-PCCleanupScript -ScriptBlock $cmd
                        }
                    }
                    else {
                        Write-Warn "No undoScript found in tweaks.json for '$($entry.TweakName)'. The tweak definition may have changed."
                    }
                }
                else {
                    Write-Err -Message "Cannot execute script undo for '$($entry.TweakName)'" -Cause 'tweaks.json not found' -Fix 'Restore tweaks.json from original ZIP.'
                }
            }
            elseif ($changeType -eq 'StartupRegistry') {
                # SECURITY: Only allow writes to known startup registry paths.
                # Prevents undo log tampering from writing to arbitrary registry keys.
                $validStartupRegPaths = @(
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'
                )
                if ($change.Path -notin $validStartupRegPaths) {
                    Write-Warn "SECURITY: StartupRegistry undo blocked -- path '$($change.Path)' is not a known startup location. Skipping."
                    Write-Log "SECURITY: Blocked StartupRegistry undo -- invalid path: $($change.Path)"
                    continue
                }
                if (-not (Test-Path $change.Path)) {
                    New-Item -Path $change.Path -Force | Out-Null
                }
                Set-ItemProperty -Path $change.Path -Name $change.Name -Value $change.Command -Force
            }
            elseif ($changeType -eq 'StartupFolder') {
                # SECURITY: Only allow renames within known startup folder locations.
                $validStartupFolders = @(
                    [System.IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup')),
                    [System.IO.Path]::GetFullPath((Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Startup'))
                )
                $filePath = [System.IO.Path]::GetFullPath($change.FilePath)
                $fileDir = [System.IO.Path]::GetDirectoryName($filePath)
                $inAllowedFolder = $false
                foreach ($allowed in $validStartupFolders) {
                    if ($fileDir -eq $allowed) { $inAllowedFolder = $true; break }
                }
                if (-not $inAllowedFolder) {
                    Write-Warn "SECURITY: StartupFolder undo blocked -- path '$($change.FilePath)' is not a known startup folder. Skipping."
                    Write-Log "SECURITY: Blocked StartupFolder undo -- invalid path: $($change.FilePath)"
                    continue
                }
                $disabledPath = "$($change.FilePath).disabled"
                if (Test-Path -LiteralPath $disabledPath) {
                    Rename-Item -LiteralPath $disabledPath -NewName $change.FileName -Force
                }
                else {
                    Write-Warn "Disabled file not found: $disabledPath"
                }
            }
        }
        catch {
            $errDetail = "Failed to undo change ($($change.Type): $($change.Name))"
            Write-Err -Message $errDetail -Cause $_.Exception.Message -Fix 'Try using System Restore Point to revert all changes.'
        }
    }

    # Remove entry from log (atomic write to prevent corruption)
    $remaining = @($log | Where-Object { $_.TweakName -ne $Name -or $_.AppliedAt -ne $entry.AppliedAt })
    $tempPath = "$($script:UndoLogPath).tmp"
    if ($remaining.Count -eq 0) {
        '[]' | Set-Content -Path $tempPath -Encoding UTF8
    }
    else {
        $remaining | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath -Encoding UTF8
    }
    Move-Item -Path $tempPath -Destination $script:UndoLogPath -Force

    Write-Success "Undone '$Name'"
    Write-Log "UndoManager: Undone '$Name'"
}

function Invoke-UndoAll {
    <#
    .SYNOPSIS
        Undoes all applied tweaks in reverse chronological order.
    .DESCRIPTION
        Iterates through the undo log in reverse order and restores
        each tweak. Used for full system restoration.
    #>
    [CmdletBinding()]
    param()

    $log = Get-AppliedTweaks
    if ($log.Count -eq 0) {
        Write-Info 'No applied tweaks to undo.'
        return
    }

    Write-Info "Undoing $($log.Count) applied tweak(s) in reverse order..."

    # Sort by AppliedAt descending (most recent first)
    $sorted = $log | Sort-Object -Property AppliedAt -Descending

    foreach ($entry in $sorted) {
        Invoke-UndoTweak -Name $entry.TweakName
    }

    Write-Success 'All applied tweaks have been undone.'
}
