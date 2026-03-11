# ==============================================================================
# PC Cleanup v2 -- SecurityCheck.ps1
# Security health snapshot. Completely read-only -- no modifications.
# ==============================================================================

function Get-DefenderStatus {
    <#
    .SYNOPSIS
        Checks Windows Defender status.
    .DESCRIPTION
        Reports whether Defender is enabled, signature age, and
        real-time protection status. Uses Get-MpComputerStatus when
        available, falls back to registry checks.
    .OUTPUTS
        [PSCustomObject] Defender status with Enabled, RealTimeProtection,
        SignatureAge, SignatureLastUpdated, and EngineVersion.
    #>
    [CmdletBinding()]
    param()

    $status = [PSCustomObject]@{
        Available          = $false
        Enabled            = $false
        RealTimeProtection = $false
        SignatureAge       = -1
        SignatureLastUpdated = ''
        EngineVersion      = ''
        Message            = ''
    }

    try {
        $mpStatus = Get-MpComputerStatus -ErrorAction Stop

        $status.Available = $true
        $status.Enabled = [bool]$mpStatus.AntivirusEnabled
        $status.RealTimeProtection = $mpStatus.RealTimeProtectionEnabled
        $status.EngineVersion = $mpStatus.AMEngineVersion

        if ($mpStatus.AntivirusSignatureLastUpdated) {
            $status.SignatureLastUpdated = $mpStatus.AntivirusSignatureLastUpdated.ToString('yyyy-MM-dd HH:mm')
            $status.SignatureAge = [int]([datetime]::Now - $mpStatus.AntivirusSignatureLastUpdated).TotalDays
        }
    }
    catch {
        # Get-MpComputerStatus not available (3rd-party AV replaces Defender, or not admin)
        $status.Message = "Could not query Defender: $($_.Exception.Message)"

        # Fall back to registry check for basic status
        try {
            $regPath = 'HKLM:\SOFTWARE\Microsoft\Windows Defender'
            if (Test-Path $regPath) {
                $status.Available = $true
                $disableVal = (Get-ItemProperty -Path "$regPath\Real-Time Protection" -Name DisableRealtimeMonitoring -ErrorAction SilentlyContinue).DisableRealtimeMonitoring
                $status.RealTimeProtection = $disableVal -ne 1
                $status.Enabled = $status.RealTimeProtection
            }
        }
        catch {
            $null = $_
        }
    }

    return $status
}

function Get-FirewallStatus {
    <#
    .SYNOPSIS
        Checks Windows Firewall status for all profiles.
    .DESCRIPTION
        Reports on Domain, Private, and Public firewall profiles.
        Uses Get-NetFirewallProfile when available, falls back to
        netsh advfirewall.
    .OUTPUTS
        [PSCustomObject[]] Firewall status for each profile.
    #>
    [CmdletBinding()]
    param()

    $results = @()

    try {
        $profiles = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($fwItem in $profiles) {
            $results += [PSCustomObject]@{
                Profile = $fwItem.Name
                Enabled = $fwItem.Enabled
            }
        }
    }
    catch {
        # Fallback to netsh parsing
        try {
            $netshOutput = netsh advfirewall show allprofiles state 2>&1
            foreach ($profileName in @('Domain', 'Private', 'Public')) {
                $enabled = $false
                if ($netshOutput -match "$profileName.*ON") {
                    $enabled = $true
                }
                $results += [PSCustomObject]@{
                    Profile = $profileName
                    Enabled = $enabled
                }
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Profile = 'Unknown'
                Enabled = $false
            }
        }
    }

    return $results
}

function Test-SMBv1Enabled {
    <#
    .SYNOPSIS
        Checks if SMBv1 is enabled (security risk).
    .DESCRIPTION
        SMBv1 is a deprecated protocol with known vulnerabilities
        (WannaCry, EternalBlue). Checks the Windows optional feature
        state, falling back to registry check.
    .OUTPUTS
        [PSCustomObject] With Enabled, Source, and Message properties.
    #>
    [CmdletBinding()]
    param()

    $result = [PSCustomObject]@{
        Enabled = $false
        Source  = ''
        Message = ''
    }

    # Try Get-WindowsOptionalFeature (requires admin on client OS)
    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName 'SMB1Protocol' -ErrorAction Stop
        $result.Enabled = $feature.State -eq 'Enabled'
        $result.Source = 'WindowsOptionalFeature'
        return $result
    }
    catch {
        $null = $_
    }

    # Fallback: check registry for SMBv1 server config
    try {
        $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
        $val = (Get-ItemProperty -Path $regPath -Name SMB1 -ErrorAction SilentlyContinue).SMB1
        if ($null -ne $val) {
            $result.Enabled = $val -ne 0
            $result.Source = 'Registry'
        }
        else {
            # If the value doesn't exist, SMBv1 may be enabled by default on older builds
            $build = Get-OSBuild
            $result.Enabled = $build -lt 17763
            $result.Source = 'BuildDefault'
            $result.Message = if ($result.Enabled) { 'SMB1 registry value not set -- likely enabled by default on this build.' } else { 'SMB1 registry value not set -- likely disabled by default on this build.' }
        }
    }
    catch {
        $result.Message = "Could not determine SMBv1 status: $($_.Exception.Message)"
    }

    return $result
}

function Get-PendingUpdates {
    <#
    .SYNOPSIS
        Counts pending Windows updates.
    .DESCRIPTION
        Uses the Windows Update COM object (Microsoft.Update.Session)
        to query for pending updates. Falls back gracefully if the
        COM object is unavailable or access is denied.
    .OUTPUTS
        [PSCustomObject] With Count, Updates (array of titles), and Message.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Returns multiple updates')]
    [CmdletBinding()]
    param()

    $result = [PSCustomObject]@{
        Count   = -1
        Updates = @()
        Message = ''
    }

    try {
        $session = New-Object -ComObject 'Microsoft.Update.Session' -ErrorAction Stop
        $searcher = $session.CreateUpdateSearcher()
        $searchResult = $searcher.Search('IsInstalled=0')

        $result.Count = $searchResult.Updates.Count
        $titles = @()
        foreach ($update in $searchResult.Updates) {
            $titles += $update.Title
        }
        $result.Updates = $titles
    }
    catch {
        $result.Message = "Could not query pending updates: $($_.Exception.Message)"
    }

    return $result
}

function Get-SecurityReport {
    <#
    .SYNOPSIS
        Generates an aggregate security health report.
    .DESCRIPTION
        Combines Defender status, firewall status, SMBv1 check,
        and pending updates into a summary with recommendations.
        Displays a formatted report to the console and returns
        the data for programmatic use.
    .OUTPUTS
        [PSCustomObject] Aggregate security report with all checks
        and an overall Grade (A/B/C/F).
    #>
    [CmdletBinding()]
    param()

    Write-Host ""
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host "      SECURITY HEALTH CHECK     " -ForegroundColor White
    Write-Host "  ==============================" -ForegroundColor White
    Write-Host ""

    $issues = 0

    # --- Defender ---
    Write-Host "  Windows Defender:" -ForegroundColor White
    $defender = Get-DefenderStatus
    if ($defender.Available) {
        if ($defender.RealTimeProtection) {
            Write-Host "    Real-time protection: ON" -ForegroundColor Green
        }
        else {
            Write-Host "    Real-time protection: OFF" -ForegroundColor Red
            $issues++
        }
        if ($defender.SignatureAge -ge 0) {
            $sigColor = if ($defender.SignatureAge -le 3) { 'Green' } elseif ($defender.SignatureAge -le 7) { 'Yellow' } else { 'Red' }
            Write-Host "    Signature age: $($defender.SignatureAge) day(s) (updated $($defender.SignatureLastUpdated))" -ForegroundColor $sigColor
            if ($defender.SignatureAge -gt 7) { $issues++ }
        }
        if ($defender.EngineVersion) {
            Write-Host "    Engine version: $($defender.EngineVersion)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "    Status: Unavailable (third-party AV or not admin)" -ForegroundColor Yellow
        if ($defender.Message) { Write-Host "    $($defender.Message)" -ForegroundColor DarkGray }
    }

    # --- Firewall ---
    Write-Host ""
    Write-Host "  Windows Firewall:" -ForegroundColor White
    $firewall = Get-FirewallStatus
    foreach ($fwProfile in $firewall) {
        $fwColor = if ($fwProfile.Enabled) { 'Green' } else { 'Red' }
        $fwStatus = if ($fwProfile.Enabled) { 'ON' } else { 'OFF' }
        Write-Host "    $($fwProfile.Profile): $fwStatus" -ForegroundColor $fwColor
        if (-not $fwProfile.Enabled) { $issues++ }
    }

    # --- SMBv1 ---
    Write-Host ""
    Write-Host "  SMBv1 Protocol:" -ForegroundColor White
    $smb = Test-SMBv1Enabled
    if ($smb.Enabled) {
        Write-Host "    Status: ENABLED (security risk -- WannaCry/EternalBlue vector)" -ForegroundColor Red
        Write-Host "    Recommendation: Disable via 'Turn Windows features on or off'" -ForegroundColor Yellow
        $issues++
    }
    else {
        Write-Host "    Status: Disabled (good)" -ForegroundColor Green
    }
    if ($smb.Message) { Write-Host "    $($smb.Message)" -ForegroundColor DarkGray }

    # --- Pending Updates ---
    Write-Host ""
    Write-Host "  Windows Updates:" -ForegroundColor White
    $updates = Get-PendingUpdates
    if ($updates.Count -ge 0) {
        $updColor = if ($updates.Count -eq 0) { 'Green' } elseif ($updates.Count -le 5) { 'Yellow' } else { 'Red' }
        Write-Host "    Pending updates: $($updates.Count) (including drivers and definitions)" -ForegroundColor $updColor
        if ($updates.Count -gt 0) {
            $issues++
            # Show first 5 update titles
            $shown = 0
            foreach ($title in $updates.Updates) {
                if ($shown -ge 5) {
                    Write-Host "    ... and $($updates.Count - 5) more" -ForegroundColor DarkGray
                    break
                }
                Write-Host "    - $title" -ForegroundColor DarkGray
                $shown++
            }
        }
    }
    else {
        Write-Host "    Could not check pending updates." -ForegroundColor Yellow
        if ($updates.Message) { Write-Host "    $($updates.Message)" -ForegroundColor DarkGray }
    }

    # --- Overall Grade ---
    $grade = if ($issues -eq 0) { 'A' } elseif ($issues -le 2) { 'B' } elseif ($issues -le 4) { 'C' } else { 'F' }
    $gradeColor = switch ($grade) { 'A' { 'Green' } 'B' { 'Yellow' } 'C' { 'DarkYellow' } 'F' { 'Red' } }

    Write-Host ""
    Write-Host "  Overall Security Grade: $grade ($issues issue(s) found)" -ForegroundColor $gradeColor
    Write-Host ""

    return [PSCustomObject]@{
        Defender   = $defender
        Firewall   = $firewall
        SMBv1      = $smb
        Updates    = $updates
        Issues     = $issues
        Grade      = $grade
    }
}
