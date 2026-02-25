# ==============================================================================
# PC Cleanup v2 -- 05-UndoManager.ps1
# Tracks applied tweaks with full original state captured at apply time.
# Enables per-tweak and bulk undo. Persists to undo_log.json between sessions.
# ==============================================================================

# Undo log lives at %LOCALAPPDATA%\PCCleanup\undo_log.json
$script:UndoLogDir = Join-Path $env:LOCALAPPDATA 'PCCleanup'
$script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'

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
        $log | ConvertTo-Json -Depth 10 | Set-Content -Path $script:UndoLogPath -Encoding UTF8

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
        return @($parsed)
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

    # Warn if OS build changed since apply
    $currentBuild = Get-OSBuild
    if ($entry.AppliedOnBuild -and $entry.AppliedOnBuild -ne $currentBuild) {
        Write-Warn "This tweak was applied on build $($entry.AppliedOnBuild). Current build is $currentBuild. Undo values may not match current OS defaults."
    }

    Write-Info "Undoing '$Name'..."

    foreach ($change in $entry.Changes) {
        try {
            $changeType = [string]$change.Type
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
        }
        catch {
            $errDetail = "Failed to undo change ($($change.Type): $($change.Name))"
            Write-Err -Message $errDetail -Cause $_.Exception.Message -Fix 'Try using System Restore Point to revert all changes.'
        }
    }

    # Remove entry from log
    $remaining = @($log | Where-Object { $_.TweakName -ne $Name -or $_.AppliedAt -ne $entry.AppliedAt })
    if ($remaining.Count -eq 0) {
        # Write empty array so the file stays valid JSON
        '[]' | Set-Content -Path $script:UndoLogPath -Encoding UTF8
    }
    else {
        $remaining | ConvertTo-Json -Depth 10 | Set-Content -Path $script:UndoLogPath -Encoding UTF8
    }

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
