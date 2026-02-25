# ==============================================================================
# PC Cleanup v2 -- 01-Utility.ps1
# Shared helper functions used by all modules
# Loaded first -- no dependencies on other project files
# ==============================================================================

function Test-IsAdmin {
    <#
    .SYNOPSIS
        Checks if the current session has administrator privileges.
    .DESCRIPTION
        Returns $true if running as admin, $false otherwise.
        Used to gate operations that require elevation.
    #>
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Success {
    <#
    .SYNOPSIS
        Writes a success message in green.
    .PARAMETER Message
        The message to display.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "  [+] $Message" -ForegroundColor Green
    Write-Log -Message "[SUCCESS] $Message"
}

function Write-Info {
    <#
    .SYNOPSIS
        Writes an informational message in cyan.
    .PARAMETER Message
        The message to display.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "  [i] $Message" -ForegroundColor Cyan
    Write-Log -Message "[INFO] $Message"
}

function Write-Warn {
    <#
    .SYNOPSIS
        Writes a warning message in yellow.
    .PARAMETER Message
        The message to display.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "  [!] $Message" -ForegroundColor Yellow
    Write-Log -Message "[WARN] $Message"
}

function Write-Err {
    <#
    .SYNOPSIS
        Writes an error message in red with cause and fix guidance.
    .PARAMETER Message
        What happened.
    .PARAMETER Cause
        Why it happened.
    .PARAMETER Fix
        What the user should do.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Cause,

        [string]$Fix
    )

    Write-Host "  [x] $Message" -ForegroundColor Red
    if ($Cause) { Write-Host "      Why: $Cause" -ForegroundColor DarkYellow }
    if ($Fix)   { Write-Host "      Fix: $Fix" -ForegroundColor DarkYellow }
    Write-Log -Message "[ERROR] $Message | Cause: $Cause | Fix: $Fix"
}

function Write-Skip {
    <#
    .SYNOPSIS
        Writes a skip message in dark gray.
    .PARAMETER Message
        The message explaining why the operation was skipped.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-Host "  [-] $Message" -ForegroundColor DarkGray
    Write-Log -Message "[SKIP] $Message"
}

function Write-Log {
    <#
    .SYNOPSIS
        Appends a timestamped message to the session log file.
    .DESCRIPTION
        Logs to %LOCALAPPDATA%\PCCleanup\logs\PCCleanup_yyyy-MM-dd.log.
        This function must NEVER throw -- all Write-* helpers depend on it.
    .PARAMETER Message
        The message to log.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Message', Justification = 'Used in string interpolation')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    try {
        $logDir = Join-Path $env:LOCALAPPDATA 'PCCleanup\logs'
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        $logFile = Join-Path $logDir "PCCleanup_$(Get-Date -Format 'yyyy-MM-dd').log"
        $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
        Add-Content -Path $logFile -Value $entry -ErrorAction SilentlyContinue
    }
    catch {
        # Intentionally swallowed -- logging must never crash the script
        $null = $_
    }
}

function Get-UserConfirmation {
    <#
    .SYNOPSIS
        Prompts the user for Y/N confirmation.
    .PARAMETER Prompt
        The question to ask.
    .PARAMETER Default
        The default answer if the user presses Enter. 'Y' or 'N'.
    .OUTPUTS
        [bool] $true if confirmed, $false otherwise.
    .EXAMPLE
        if (Get-UserConfirmation "Apply safe tweaks?") { Invoke-TweakSet -Category Privacy }
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Params used in string interpolation and expressions')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [ValidateSet('Y', 'N')]
        [string]$Default = 'Y'
    )

    try {
        $response = Read-Host "$Prompt [Y/N] (default: $Default)"
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $Default -eq 'Y'
        }
        return $response.Trim().ToUpper().StartsWith('Y')
    }
    catch {
        # Non-interactive pipeline -- return the default
        return $Default -eq 'Y'
    }
}

function Pause-Script {
    <#
    .SYNOPSIS
        Pauses execution until the user presses Enter.
    .EXAMPLE
        Pause-Script
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '')]
    [CmdletBinding()]
    param()

    try {
        Read-Host 'Press Enter to continue...'
    }
    catch {
        # Non-interactive pipeline -- skip the pause
        $null = $_
    }
}

function Format-FileSize {
    <#
    .SYNOPSIS
        Converts bytes to human-readable file size (KB, MB, GB).
    .PARAMETER Bytes
        The number of bytes to format.
    .OUTPUTS
        [string] Formatted file size string.
    .EXAMPLE
        Format-FileSize -Bytes 1536  # Returns "1.50 KB"
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Bytes', Justification = 'Used in comparison expressions and format operator')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [long]$Bytes
    )

    if ($Bytes -ge 1GB) {
        return '{0:N2} GB' -f ($Bytes / 1GB)
    }
    if ($Bytes -ge 1MB) {
        return '{0:N2} MB' -f ($Bytes / 1MB)
    }
    if ($Bytes -ge 1KB) {
        return '{0:N2} KB' -f ($Bytes / 1KB)
    }
    return "$Bytes bytes"
}
