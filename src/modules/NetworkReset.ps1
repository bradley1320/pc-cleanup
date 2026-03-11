# ==============================================================================
# PC Cleanup v2 -- NetworkReset.ps1
# Network troubleshooting: DNS flush, Winsock reset, TCP/IP reset.
# ISOLATED from optimization flow -- NOT included in Full Tune-Up.
# Heavy warnings about VPN/Hyper-V/Docker/static IP impact.
# ==============================================================================

function Reset-DNSCache {
    <#
    .SYNOPSIS
        Flushes the DNS resolver cache.
    .DESCRIPTION
        Runs ipconfig /flushdns. Low-risk, no reboot needed.
    .PARAMETER WhatIf
        Preview mode -- show what would happen without executing.
    .OUTPUTS
        [bool] $true if succeeded, $false otherwise.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Application-level WhatIf')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'Application-level WhatIf')]
    [CmdletBinding()]
    param(
        [switch]$WhatIf
    )

    if ($WhatIf) {
        Write-Info 'WhatIf: Would flush DNS resolver cache (ipconfig /flushdns).'
        return $true
    }

    try {
        $result = & ipconfig /flushdns 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success 'DNS resolver cache flushed.'
            return $true
        }
        else {
            Write-Warn "DNS flush returned exit code $LASTEXITCODE."
            Write-Log "DNS flush output: $($result -join '; ')"
            return $false
        }
    }
    catch {
        Write-Err -Message 'Failed to flush DNS cache' -Cause $_.Exception.Message -Fix 'Try running ipconfig /flushdns manually from an elevated prompt.'
        return $false
    }
}

function Reset-WinsockCatalog {
    <#
    .SYNOPSIS
        Resets the Winsock catalog to clean state.
    .DESCRIPTION
        Runs netsh winsock reset. Requires admin privileges and a reboot.
        WARNING: Destroys Hyper-V virtual switches, Docker networking,
        VPN configs, and LSP entries.
    .PARAMETER WhatIf
        Preview mode -- show what would happen without executing.
    .OUTPUTS
        [bool] $true if succeeded, $false otherwise.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Application-level WhatIf')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'Application-level WhatIf')]
    [CmdletBinding()]
    param(
        [switch]$WhatIf
    )

    if (-not (Test-IsAdmin)) {
        Write-Err -Message 'Winsock reset requires administrator privileges' -Cause 'Not running as admin' -Fix 'Right-click Run.bat and select Run as Administrator.'
        return $false
    }

    if ($WhatIf) {
        Write-Info 'WhatIf: Would reset Winsock catalog (netsh winsock reset). Requires reboot.'
        return $true
    }

    try {
        $result = & netsh winsock reset 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success 'Winsock catalog reset. A reboot is required.'
            return $true
        }
        else {
            Write-Warn "Winsock reset returned exit code $LASTEXITCODE."
            Write-Log "Winsock reset output: $($result -join '; ')"
            return $false
        }
    }
    catch {
        Write-Err -Message 'Failed to reset Winsock catalog' -Cause $_.Exception.Message -Fix 'Try running netsh winsock reset manually from an elevated prompt.'
        return $false
    }
}

function Reset-TCPIPStack {
    <#
    .SYNOPSIS
        Resets the TCP/IP stack.
    .DESCRIPTION
        Runs netsh int ip reset. Requires admin privileges and a reboot.
        WARNING: Resets all static IP configurations, custom MTU settings,
        and network interface parameters.
    .PARAMETER WhatIf
        Preview mode -- show what would happen without executing.
    .OUTPUTS
        [bool] $true if succeeded, $false otherwise.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Application-level WhatIf')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'Application-level WhatIf')]
    [CmdletBinding()]
    param(
        [switch]$WhatIf
    )

    if (-not (Test-IsAdmin)) {
        Write-Err -Message 'TCP/IP reset requires administrator privileges' -Cause 'Not running as admin' -Fix 'Right-click Run.bat and select Run as Administrator.'
        return $false
    }

    if ($WhatIf) {
        Write-Info 'WhatIf: Would reset TCP/IP stack (netsh int ip reset). Requires reboot.'
        return $true
    }

    try {
        $result = & netsh int ip reset 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success 'TCP/IP stack reset. A reboot is required.'
            return $true
        }
        else {
            Write-Warn "TCP/IP reset returned exit code $LASTEXITCODE."
            Write-Log "TCP/IP reset output: $($result -join '; ')"
            return $false
        }
    }
    catch {
        Write-Err -Message 'Failed to reset TCP/IP stack' -Cause $_.Exception.Message -Fix 'Try running netsh int ip reset manually from an elevated prompt.'
        return $false
    }
}

function Clear-ARPCache {
    <#
    .SYNOPSIS
        Clears the ARP cache.
    .DESCRIPTION
        Runs netsh interface ip delete arpcache. Requires admin privileges.
    .PARAMETER WhatIf
        Preview mode -- show what would happen without executing.
    .OUTPUTS
        [bool] $true if succeeded, $false otherwise.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'Application-level WhatIf')]
    [CmdletBinding()]
    param(
        [switch]$WhatIf
    )

    if (-not (Test-IsAdmin)) {
        Write-Err -Message 'ARP cache clear requires administrator privileges' -Cause 'Not running as admin' -Fix 'Right-click Run.bat and select Run as Administrator.'
        return $false
    }

    if ($WhatIf) {
        Write-Info 'WhatIf: Would clear ARP cache (netsh interface ip delete arpcache).'
        return $true
    }

    try {
        $result = & netsh interface ip delete arpcache 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success 'ARP cache cleared.'
            return $true
        }
        else {
            Write-Warn "ARP cache clear returned exit code $LASTEXITCODE."
            Write-Log "ARP cache clear output: $($result -join '; ')"
            return $false
        }
    }
    catch {
        Write-Err -Message 'Failed to clear ARP cache' -Cause $_.Exception.Message -Fix 'Try running the command manually from an elevated prompt.'
        return $false
    }
}

function Show-NetworkResetMenu {
    <#
    .SYNOPSIS
        Interactive menu for network troubleshooting operations.
    .DESCRIPTION
        Displays warnings about VPN/Hyper-V/Docker/static IP impact before
        executing any operations. Requires explicit user confirmation.
        NOT included in Full Tune-Up -- standalone troubleshooting only.
    .PARAMETER WhatIf
        Preview mode -- show what would happen without executing.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'WhatIf passed to sub-functions')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSupportsShouldProcess', '', Justification = 'Application-level WhatIf')]
    [CmdletBinding()]
    param(
        [switch]$WhatIf
    )

    Write-Host ""
    Write-Host "  ==============================" -ForegroundColor Yellow
    Write-Host "       NETWORK RESET TOOLS      " -ForegroundColor Yellow
    Write-Host "  ==============================" -ForegroundColor Yellow
    Write-Host ""
    Write-Warn '*** WARNING: Network reset operations can break existing configurations ***'
    Write-Host ""
    Write-Host "  The following may be affected:" -ForegroundColor Yellow
    Write-Host "    - VPN connections and configurations" -ForegroundColor Yellow
    Write-Host "    - Hyper-V virtual switches" -ForegroundColor Yellow
    Write-Host "    - Docker networking" -ForegroundColor Yellow
    Write-Host "    - Static IP addresses and custom DNS" -ForegroundColor Yellow
    Write-Host "    - Custom MTU settings" -ForegroundColor Yellow
    Write-Host "    - Winsock LSP entries (antivirus network filters)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Flush DNS Cache            (low risk, no reboot)" -ForegroundColor Green
    Write-Host "  2. Clear ARP Cache             (low risk, requires admin)" -ForegroundColor Green
    Write-Host "  3. Reset Winsock Catalog       (medium risk, requires reboot)" -ForegroundColor Yellow
    Write-Host "  4. Reset TCP/IP Stack          (high risk, requires reboot)" -ForegroundColor Red
    Write-Host "  5. Full Network Reset (1-4)    (high risk, requires reboot)" -ForegroundColor Red
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

    $needsReboot = $false

    switch ($choice) {
        '1' {
            Reset-DNSCache -WhatIf:$WhatIf
        }
        '2' {
            Clear-ARPCache -WhatIf:$WhatIf
        }
        '3' {
            if ($WhatIf -or (Get-UserConfirmation -Prompt 'Reset Winsock catalog? This requires a reboot.' -Default 'N')) {
                Reset-WinsockCatalog -WhatIf:$WhatIf
                $needsReboot = $true
            }
            else {
                Write-Skip 'Winsock reset cancelled.'
            }
        }
        '4' {
            if ($WhatIf -or (Get-UserConfirmation -Prompt 'Reset TCP/IP stack? This resets static IPs and requires a reboot.' -Default 'N')) {
                Reset-TCPIPStack -WhatIf:$WhatIf
                $needsReboot = $true
            }
            else {
                Write-Skip 'TCP/IP reset cancelled.'
            }
        }
        '5' {
            if ($WhatIf -or (Get-UserConfirmation -Prompt 'Run FULL network reset (DNS + ARP + Winsock + TCP/IP)? Requires reboot.' -Default 'N')) {
                Reset-DNSCache -WhatIf:$WhatIf
                Clear-ARPCache -WhatIf:$WhatIf
                Reset-WinsockCatalog -WhatIf:$WhatIf
                Reset-TCPIPStack -WhatIf:$WhatIf
                $needsReboot = $true
            }
            else {
                Write-Skip 'Full network reset cancelled.'
            }
        }
        default {
            Write-Warn "Unrecognized input: $choice"
        }
    }

    if ($needsReboot -and -not $WhatIf) {
        Write-Host ""
        Write-Warn 'A reboot is required to complete the network reset.'
        Write-Warn 'Network connectivity may be temporarily lost until restart.'
        Write-Host ""
    }
}
