# ==============================================================================
# PC Cleanup v2 -- StartupManager.ps1
# View and manage startup programs with publisher, description, and risk context.
# Cross-references apps-critical.json and apps-bloat.json for risk indicators.
# ==============================================================================

function Get-StartupPrograms {
    <#
    .SYNOPSIS
        Scans and returns all startup programs with metadata.
    .DESCRIPTION
        Scans registry Run keys (HKCU + HKLM) and startup folders.
        For each entry: resolves file path, extracts publisher and
        description from file properties. Cross-references against
        apps-critical.json and apps-bloat.json. Handles orphaned entries
        (missing executables) gracefully with "(file missing)" display.
    .OUTPUTS
        [PSCustomObject[]] Array with Name, Command, ExePath, Publisher,
        Description, Source, Risk, RiskReason, IsOrphaned properties.
    .EXAMPLE
        Get-StartupPrograms
        Get-StartupPrograms | Where-Object { $_.Risk -eq 'bloat' }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Returns multiple startup programs')]
    [CmdletBinding()]
    param()

    # Load classification databases
    $critical = Get-StartupClassification -Type 'critical'
    $bloat = Get-StartupClassification -Type 'bloat'

    $programs = @()

    # --- Registry Run keys ---
    $regSources = @(
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';    Scope = 'User' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';    Scope = 'Machine' }
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Scope = 'User (RunOnce)' }
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; Scope = 'Machine (RunOnce)' }
    )

    foreach ($source in $regSources) {
        if (-not (Test-Path $source.Path)) { continue }

        try {
            $regKey = Get-Item -LiteralPath $source.Path -ErrorAction SilentlyContinue
            if ($null -eq $regKey) { continue }

            foreach ($name in $regKey.GetValueNames()) {
                if ([string]::IsNullOrWhiteSpace($name)) { continue }

                $command = $regKey.GetValue($name)
                if ([string]::IsNullOrWhiteSpace($command)) { continue }

                $exePath = Resolve-StartupExePath -Command $command
                $fileInfo = Get-StartupFileInfo -ExePath $exePath

                $riskInfo = Get-StartupRisk -Name $name -ExePath $exePath -CriticalList $critical -BloatList $bloat

                $programs += [PSCustomObject]@{
                    Name        = $name
                    Command     = $command
                    ExePath     = $exePath
                    Publisher   = $fileInfo.Publisher
                    Description = $fileInfo.Description
                    Source      = "Registry ($($source.Scope))"
                    SourcePath  = $source.Path
                    SourceType  = 'Registry'
                    Risk        = $riskInfo.Risk
                    RiskReason  = $riskInfo.Reason
                    IsOrphaned  = $fileInfo.IsOrphaned
                }
            }
        }
        catch {
            Write-Log "StartupManager: Error reading $($source.Path): $($_.Exception.Message)"
        }
    }

    # --- Startup folders ---
    $startupFolders = @(
        @{ Path = [System.IO.Path]::Combine($env:APPDATA, 'Microsoft\Windows\Start Menu\Programs\Startup'); Scope = 'User' }
        @{ Path = [System.IO.Path]::Combine($env:ProgramData, 'Microsoft\Windows\Start Menu\Programs\Startup'); Scope = 'Machine' }
    )

    foreach ($folder in $startupFolders) {
        if (-not (Test-Path -LiteralPath $folder.Path)) { continue }

        try {
            $items = Get-ChildItem -LiteralPath $folder.Path -File -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                $exePath = $item.FullName
                # Shortcuts (.lnk) -- resolve target
                if ($item.Extension -eq '.lnk') {
                    $exePath = Resolve-ShortcutTarget -LnkPath $item.FullName
                }

                $fileInfo = Get-StartupFileInfo -ExePath $exePath
                $riskInfo = Get-StartupRisk -Name $item.BaseName -ExePath $exePath -CriticalList $critical -BloatList $bloat

                $programs += [PSCustomObject]@{
                    Name        = $item.BaseName
                    Command     = $item.FullName
                    ExePath     = $exePath
                    Publisher   = $fileInfo.Publisher
                    Description = $fileInfo.Description
                    Source      = "Startup Folder ($($folder.Scope))"
                    SourcePath  = $folder.Path
                    SourceType  = 'Folder'
                    Risk        = $riskInfo.Risk
                    RiskReason  = $riskInfo.Reason
                    IsOrphaned  = $fileInfo.IsOrphaned
                }
            }
        }
        catch {
            Write-Log "StartupManager: Error reading startup folder $($folder.Path): $($_.Exception.Message)"
        }
    }

    return $programs
}

function Disable-StartupProgram {
    <#
    .SYNOPSIS
        Disables a startup program and registers undo.
    .DESCRIPTION
        Removes the startup entry from registry or renames the startup
        folder file. Records the original state in UndoManager for
        restoration via Enable-StartupProgram.
    .PARAMETER Name
        The name of the startup program to disable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $programs = Get-StartupPrograms
    $program = $programs | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

    if ($null -eq $program) {
        Write-Warn "Startup program '$Name' not found."
        return
    }

    # Warn for critical programs
    if ($program.Risk -eq 'critical') {
        Write-Warn "WARNING: '$Name' is flagged as critical -- $($program.RiskReason)"
        Write-Warn 'Disabling this may cause system issues.'
        if (-not (Get-UserConfirmation -Prompt "Are you sure you want to disable '$Name'?" -Default 'N')) {
            Write-Info "Skipped '$Name'."
            return
        }
    }

    # Build undo record
    $changes = @()

    if ($program.SourceType -eq 'Registry') {
        # Capture current state
        $changes += [PSCustomObject]@{
            Type        = 'StartupRegistry'
            Path        = $program.SourcePath
            Name        = $program.Name
            Command     = $program.Command
        }

        # Remove the registry value
        try {
            Remove-ItemProperty -Path $program.SourcePath -Name $program.Name -Force
            Write-Log "StartupManager: Removed registry startup entry '$Name' from $($program.SourcePath)"
        }
        catch {
            Write-Err -Message "Failed to disable startup program '$Name'" -Cause $_.Exception.Message -Fix 'Run as Administrator.'
            return
        }
    }
    elseif ($program.SourceType -eq 'Folder') {
        $changes += [PSCustomObject]@{
            Type       = 'StartupFolder'
            FilePath   = $program.Command
            FileName   = [System.IO.Path]::GetFileName($program.Command)
        }

        # Rename file to disable (append .disabled)
        try {
            $disabledPath = "$($program.Command).disabled"
            Rename-Item -LiteralPath $program.Command -NewName ([System.IO.Path]::GetFileName($disabledPath)) -Force
            Write-Log "StartupManager: Renamed startup file '$($program.Command)' to .disabled"
        }
        catch {
            Write-Err -Message "Failed to disable startup program '$Name'" -Cause $_.Exception.Message -Fix 'Check file permissions.'
            return
        }
    }

    # Register with UndoManager
    Register-AppliedTweak -Name "Startup_$Name" -Changes $changes -Category 'Startup'

    Write-Success "Disabled startup program: $Name"
}

function Enable-StartupProgram {
    <#
    .SYNOPSIS
        Re-enables a previously disabled startup program.
    .DESCRIPTION
        Restores the startup entry from undo data stored in UndoManager.
    .PARAMETER Name
        The name of the startup program to re-enable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $applied = Get-AppliedTweaks
    $entry = $applied | Where-Object { $_.TweakName -eq "Startup_$Name" } | Select-Object -Last 1

    if ($null -eq $entry) {
        Write-Warn "No undo data found for startup program '$Name'."
        return
    }

    foreach ($change in $entry.Changes) {
        try {
            $changeType = [string]$change.Type
            if ($changeType -eq 'StartupRegistry') {
                # Restore registry value
                if (-not (Test-Path $change.Path)) {
                    New-Item -Path $change.Path -Force | Out-Null
                }
                Set-ItemProperty -Path $change.Path -Name $change.Name -Value $change.Command -Force
                Write-Log "StartupManager: Restored registry startup entry '$($change.Name)'"
            }
            elseif ($changeType -eq 'StartupFolder') {
                # Rename file back (remove .disabled)
                $disabledPath = "$($change.FilePath).disabled"
                if (Test-Path -LiteralPath $disabledPath) {
                    Rename-Item -LiteralPath $disabledPath -NewName $change.FileName -Force
                    Write-Log "StartupManager: Restored startup file '$($change.FileName)'"
                }
                else {
                    Write-Warn "Disabled file not found: $disabledPath"
                }
            }
        }
        catch {
            Write-Err -Message "Failed to re-enable '$Name'" -Cause $_.Exception.Message -Fix 'Try manually restoring the startup entry.'
        }
    }

    # Remove from undo log (uses $script:UndoLogPath from UndoManager)
    $remaining = @($applied | Where-Object { $_.TweakName -ne "Startup_$Name" -or $_.AppliedAt -ne $entry.AppliedAt })
    if ($remaining.Count -eq 0) {
        '[]' | Set-Content -Path $script:UndoLogPath -Encoding UTF8
    }
    else {
        $remaining | ConvertTo-Json -Depth 10 | Set-Content -Path $script:UndoLogPath -Encoding UTF8
    }

    Write-Success "Re-enabled startup program: $Name"
}

# --- Internal helper functions ---

function Resolve-StartupExePath {
    <#
    .SYNOPSIS
        Extracts the executable path from a startup command string.
    .DESCRIPTION
        Startup registry values contain full command lines with arguments.
        This function extracts just the executable path, handling quoted
        paths, arguments, and environment variables.
    .PARAMETER Command
        The raw command string from the registry.
    .OUTPUTS
        [string] The resolved executable path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command
    )

    $cmd = $Command.Trim()

    # Handle quoted paths: "C:\Program Files\app.exe" --args
    if ($cmd.StartsWith('"')) {
        $endQuote = $cmd.IndexOf('"', 1)
        if ($endQuote -gt 1) {
            return [System.Environment]::ExpandEnvironmentVariables($cmd.Substring(1, $endQuote - 1))
        }
    }

    # Unquoted path: split on first space that follows a valid extension
    $extensions = @('.exe', '.bat', '.cmd', '.com', '.ps1', '.vbs', '.wsf')
    foreach ($ext in $extensions) {
        $idx = $cmd.IndexOf($ext, [System.StringComparison]::OrdinalIgnoreCase)
        if ($idx -ge 0) {
            return [System.Environment]::ExpandEnvironmentVariables($cmd.Substring(0, $idx + $ext.Length))
        }
    }

    # Fallback: return the entire command
    return [System.Environment]::ExpandEnvironmentVariables($cmd)
}

function Get-StartupFileInfo {
    <#
    .SYNOPSIS
        Extracts publisher and description from an executable's file properties.
    .PARAMETER ExePath
        The path to the executable file.
    .OUTPUTS
        [PSCustomObject] With Publisher, Description, and IsOrphaned properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ExePath
    )

    $result = [PSCustomObject]@{
        Publisher   = ''
        Description = ''
        IsOrphaned  = $false
    }

    if ([string]::IsNullOrWhiteSpace($ExePath)) {
        $result.IsOrphaned = $true
        return $result
    }

    if (-not (Test-Path -LiteralPath $ExePath)) {
        $result.IsOrphaned = $true
        $result.Description = '(file missing)'
        return $result
    }

    try {
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExePath)
        $result.Publisher = if ($versionInfo.CompanyName) { $versionInfo.CompanyName } else { '' }
        $result.Description = if ($versionInfo.FileDescription) { $versionInfo.FileDescription } else { '' }
    }
    catch {
        # Can't read file properties -- not critical
        $null = $_
    }

    return $result
}

function Resolve-ShortcutTarget {
    <#
    .SYNOPSIS
        Resolves the target path of a .lnk shortcut file.
    .PARAMETER LnkPath
        The path to the .lnk file.
    .OUTPUTS
        [string] The resolved target path, or the .lnk path if resolution fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LnkPath
    )

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($LnkPath)
        $target = $shortcut.TargetPath
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
        if ($target) { return $target }
    }
    catch {
        $null = $_
    }

    return $LnkPath
}

function Get-StartupClassification {
    <#
    .SYNOPSIS
        Loads the startup program classification database.
    .PARAMETER Type
        Either 'critical' or 'bloat'.
    .OUTPUTS
        [array] The entries array from the JSON file, or empty array if not found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('critical', 'bloat')]
        [string]$Type
    )

    $fileName = "apps-$Type.json"
    $filePath = Join-Path $script:ConfigPath $fileName

    if (-not (Test-Path $filePath)) {
        Write-Log "StartupManager: $fileName not found at $filePath"
        return @()
    }

    try {
        $data = Get-Content -Path $filePath -Raw | ConvertFrom-Json
        return @($data.entries)
    }
    catch {
        Write-Log "StartupManager: Error parsing $fileName -- $($_.Exception.Message)"
        return @()
    }
}

function Get-StartupRisk {
    <#
    .SYNOPSIS
        Determines the risk classification of a startup program.
    .DESCRIPTION
        Cross-references the program name and executable path against
        the critical and bloat lists using regex pattern matching.
    .PARAMETER Name
        The startup program name.
    .PARAMETER ExePath
        The executable path.
    .PARAMETER CriticalList
        The loaded critical apps entries.
    .PARAMETER BloatList
        The loaded bloat apps entries.
    .OUTPUTS
        [PSCustomObject] With Risk (critical/bloat/normal) and Reason properties.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$ExePath,

        [array]$CriticalList,

        [array]$BloatList
    )

    $exeFileName = ''
    if ($ExePath) {
        $exeFileName = [System.IO.Path]::GetFileName($ExePath)
    }

    # Check critical list first (higher priority)
    foreach ($entry in $CriticalList) {
        if ($entry.pattern -and ($exeFileName -match $entry.pattern -or $Name -match $entry.pattern)) {
            return [PSCustomObject]@{
                Risk   = 'critical'
                Reason = $entry.description
            }
        }
    }

    # Check bloat list
    foreach ($entry in $BloatList) {
        if ($entry.pattern -and ($exeFileName -match $entry.pattern -or $Name -match $entry.pattern)) {
            return [PSCustomObject]@{
                Risk   = 'bloat'
                Reason = $entry.description
            }
        }
    }

    return [PSCustomObject]@{
        Risk   = 'normal'
        Reason = ''
    }
}
