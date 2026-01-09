<#
.SYNOPSIS
    PC Cleanup Tool - A fancy terminal-based system optimization utility
.DESCRIPTION
    Cleans temp files, disables startup bloat, optimizes performance settings
.NOTES
    Run as Administrator for full functionality
#>

# Require admin for some operations
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ═══════════════════════════════════════════════════════════════════════════════
# COLORS AND STYLING
# ═══════════════════════════════════════════════════════════════════════════════

function Write-Gradient {
    param([string]$Text, [string[]]$Colors)
    $chars = $Text.ToCharArray()
    $colorIndex = 0
    foreach ($char in $chars) {
        Write-Host $char -ForegroundColor $Colors[$colorIndex % $Colors.Count] -NoNewline
        $colorIndex++
    }
    Write-Host ""
}

function Write-Colored {
    param([string]$Text, [ConsoleColor]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

function Write-Success { param([string]$Text) Write-Host "  [✓] $Text" -ForegroundColor Green }
function Write-Info { param([string]$Text) Write-Host "  [i] $Text" -ForegroundColor Cyan }
function Write-Warn { param([string]$Text) Write-Host "  [!] $Text" -ForegroundColor Yellow }
function Write-Err { param([string]$Text) Write-Host "  [✗] $Text" -ForegroundColor Red }

function Show-ProgressBar {
    param([int]$Percent, [string]$Status = "")
    $width = 40
    $filled = [math]::Floor($width * $Percent / 100)
    $empty = $width - $filled
    $bar = "█" * $filled + "░" * $empty
    Write-Host "`r  [$bar] $Percent% $Status" -NoNewline -ForegroundColor Cyan
    if ($Percent -eq 100) { Write-Host "" }
}

# ═══════════════════════════════════════════════════════════════════════════════
# ASCII ART BANNER
# ═══════════════════════════════════════════════════════════════════════════════

function Show-Banner {
    Clear-Host
    $banner = @"

"@
    
    # Gradient colors for the banner
    $line1 = "  ██████╗  ██████╗     ██████╗██╗     ███████╗ █████╗ ███╗   ██╗"
    $line2 = "  ██╔══██╗██╔════╝    ██╔════╝██║     ██╔════╝██╔══██╗████╗  ██║"
    $line3 = "  ██████╔╝██║         ██║     ██║     █████╗  ███████║██╔██╗ ██║"
    $line4 = "  ██╔═══╝ ██║         ██║     ██║     ██╔══╝  ██╔══██║██║╚██╗██║"
    $line5 = "  ██║     ╚██████╗    ╚██████╗███████╗███████╗██║  ██║██║ ╚████║"
    $line6 = "  ╚═╝      ╚═════╝     ╚═════╝╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝"
    
    Write-Host ""
    Write-Host $line1 -ForegroundColor Cyan
    Write-Host $line2 -ForegroundColor Cyan
    Write-Host $line3 -ForegroundColor Magenta
    Write-Host $line4 -ForegroundColor Magenta
    Write-Host $line5 -ForegroundColor Blue
    Write-Host $line6 -ForegroundColor Blue
    Write-Host ""
    Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "    System Optimization Toolkit v1.0" -ForegroundColor White
    Write-Host "    github.com/yourusername/pc-clean" -ForegroundColor DarkGray
    Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host ""
    
    if (-not $isAdmin) {
        Write-Warn "Running without Administrator privileges - some features limited"
        Write-Host ""
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════════════════════════════════

function Show-Menu {
    Write-Host "  ┌────────────────────────────────────────────────────────────┐" -ForegroundColor DarkCyan
    Write-Host "  │                      MAIN MENU                             │" -ForegroundColor DarkCyan
    Write-Host "  ├────────────────────────────────────────────────────────────┤" -ForegroundColor DarkCyan
    Write-Host "  │                                                            │" -ForegroundColor DarkCyan
    Write-Host "  │   [1]  Quick Clean      - Temp files, cache, recycle bin   │" -ForegroundColor DarkCyan
    Write-Host "  │   [2]  Startup Manager  - Disable bloat programs           │" -ForegroundColor DarkCyan
    Write-Host "  │   [3]  Performance Mode - Optimize power & visuals         │" -ForegroundColor DarkCyan
    Write-Host "  │   [4]  Network Reset    - Flush DNS, reset stack           │" -ForegroundColor DarkCyan
    Write-Host "  │   [5]  Disk Analysis    - Show what's eating space         │" -ForegroundColor DarkCyan
    Write-Host "  │   [6]  Full Tune-Up     - Run all optimizations            │" -ForegroundColor DarkCyan
    Write-Host "  │                                                            │" -ForegroundColor DarkCyan
    Write-Host "  │   [0]  Exit                                                │" -ForegroundColor DarkCyan
    Write-Host "  │                                                            │" -ForegroundColor DarkCyan
    Write-Host "  └────────────────────────────────────────────────────────────┘" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Select an option: " -NoNewline -ForegroundColor Yellow
}

# ═══════════════════════════════════════════════════════════════════════════════
# CLEANUP FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-QuickClean {
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Green
    Write-Host "  │                    QUICK CLEAN                              │" -ForegroundColor Green
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Green
    Write-Host ""
    
    $totalCleaned = 0
    
    # Windows Temp
    Write-Info "Cleaning Windows Temp folder..."
    $tempPath = "$env:TEMP"
    $before = (Get-ChildItem $tempPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    Remove-Item "$tempPath\*" -Recurse -Force -ErrorAction SilentlyContinue
    $after = (Get-ChildItem $tempPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    $cleaned = [math]::Round($before - $after, 2)
    $totalCleaned += $cleaned
    Write-Success "Cleaned $cleaned MB from Temp"
    
    # Windows Temp (System)
    Write-Info "Cleaning System Temp folder..."
    $sysTempPath = "C:\Windows\Temp"
    $before = (Get-ChildItem $sysTempPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    Remove-Item "$sysTempPath\*" -Recurse -Force -ErrorAction SilentlyContinue
    $after = (Get-ChildItem $sysTempPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
    $cleaned = [math]::Round($before - $after, 2)
    $totalCleaned += $cleaned
    Write-Success "Cleaned $cleaned MB from System Temp"
    
    # Prefetch
    if ($isAdmin) {
        Write-Info "Cleaning Prefetch..."
        $prefetchPath = "C:\Windows\Prefetch"
        $before = (Get-ChildItem $prefetchPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
        Remove-Item "$prefetchPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        $after = (Get-ChildItem $prefetchPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
        $cleaned = [math]::Round($before - $after, 2)
        $totalCleaned += $cleaned
        Write-Success "Cleaned $cleaned MB from Prefetch"
    } else {
        Write-Warn "Skipping Prefetch (requires Admin)"
    }
    
    # Recycle Bin
    Write-Info "Emptying Recycle Bin..."
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Success "Recycle Bin emptied"
    } catch {
        Write-Warn "Could not empty Recycle Bin"
    }
    
    # Browser Caches
    Write-Info "Cleaning browser caches..."
    
    # Chrome
    $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    if (Test-Path $chromePath) {
        $before = (Get-ChildItem $chromePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
        Remove-Item "$chromePath\*" -Recurse -Force -ErrorAction SilentlyContinue
        $cleaned = [math]::Round($before, 2)
        $totalCleaned += $cleaned
        Write-Success "Cleaned $cleaned MB from Chrome cache"
    }
    
    # Edge
    $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    if (Test-Path $edgePath) {
        $before = (Get-ChildItem $edgePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
        Remove-Item "$edgePath\*" -Recurse -Force -ErrorAction SilentlyContinue
        $cleaned = [math]::Round($before, 2)
        $totalCleaned += $cleaned
        Write-Success "Cleaned $cleaned MB from Edge cache"
    }
    
    # Firefox
    $firefoxPath = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $firefoxPath) {
        Get-ChildItem $firefoxPath -Directory | ForEach-Object {
            $cachePath = "$($_.FullName)\cache2"
            if (Test-Path $cachePath) {
                $before = (Get-ChildItem $cachePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
                Remove-Item "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
                $cleaned = [math]::Round($before, 2)
                $totalCleaned += $cleaned
            }
        }
        Write-Success "Cleaned Firefox cache"
    }
    
    # Windows Update Cache
    if ($isAdmin) {
        Write-Info "Cleaning Windows Update cache..."
        $wuPath = "C:\Windows\SoftwareDistribution\Download"
        if (Test-Path $wuPath) {
            $before = (Get-ChildItem $wuPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
            Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
            Remove-Item "$wuPath\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Service wuauserv -ErrorAction SilentlyContinue
            $after = (Get-ChildItem $wuPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
            $cleaned = [math]::Round($before - $after, 2)
            $totalCleaned += $cleaned
            Write-Success "Cleaned $cleaned MB from Windows Update cache"
        }
    } else {
        Write-Warn "Skipping Windows Update cache (requires Admin)"
    }
    
    Write-Host ""
    Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host "  Total space recovered: $([math]::Round($totalCleaned, 2)) MB" -ForegroundColor Green
    Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor Green
    
    Pause-Script
}

# ═══════════════════════════════════════════════════════════════════════════════
# STARTUP MANAGER
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-StartupManager {
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Yellow
    Write-Host "  │                   STARTUP MANAGER                           │" -ForegroundColor Yellow
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Yellow
    Write-Host ""
    
    # Get startup items
    Write-Info "Scanning startup programs..."
    Write-Host ""
    
    $startupItems = @()
    
    # Registry Run keys
    $regPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    )
    
    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            $items = Get-ItemProperty $path -ErrorAction SilentlyContinue
            $items.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                $startupItems += [PSCustomObject]@{
                    Name = $_.Name
                    Path = $path
                    Command = $_.Value
                    Type = "Registry"
                }
            }
        }
    }
    
    if ($startupItems.Count -eq 0) {
        Write-Info "No startup items found in registry"
    } else {
        Write-Host "  Found $($startupItems.Count) startup items:" -ForegroundColor Cyan
        Write-Host ""
        
        $i = 1
        foreach ($item in $startupItems) {
            $displayName = $item.Name
            if ($displayName.Length -gt 30) { $displayName = $displayName.Substring(0, 27) + "..." }
            Write-Host "    [$i] $displayName" -ForegroundColor White
            $i++
        }
        
        Write-Host ""
        Write-Host "    [A] Disable common bloat automatically" -ForegroundColor Yellow
        Write-Host "    [0] Back to main menu" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Enter number to toggle, A for auto-clean, or 0 to exit: " -NoNewline -ForegroundColor Yellow
        
        $choice = Read-Host
        
        if ($choice -eq "A" -or $choice -eq "a") {
            # Common bloat programs to disable
            $bloatPatterns = @(
                "*Spotify*", "*Discord*", "*Steam*", "*Epic*", "*Origin*",
                "*Adobe*", "*Skype*", "*OneDrive*", "*Teams*", "*iTunes*",
                "*QuickTime*", "*Dropbox*", "*Google*Update*", "*Cortana*"
            )
            
            $disabled = 0
            foreach ($item in $startupItems) {
                foreach ($pattern in $bloatPatterns) {
                    if ($item.Name -like $pattern -or $item.Command -like $pattern) {
                        try {
                            Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction Stop
                            Write-Success "Disabled: $($item.Name)"
                            $disabled++
                        } catch {
                            Write-Err "Could not disable: $($item.Name)"
                        }
                        break
                    }
                }
            }
            
            Write-Host ""
            Write-Host "  Disabled $disabled startup items" -ForegroundColor Green
        }
    }
    
    Pause-Script
}

# ═══════════════════════════════════════════════════════════════════════════════
# PERFORMANCE MODE
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-PerformanceMode {
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Magenta
    Write-Host "  │                   PERFORMANCE MODE                          │" -ForegroundColor Magenta
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Magenta
    Write-Host ""
    
    # Power Plan
    Write-Info "Setting High Performance power plan..."
    try {
        powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
        if ($LASTEXITCODE -ne 0) {
            # High Performance might not exist, try to create it
            powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
            powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
        }
        Write-Success "Power plan set to High Performance"
    } catch {
        Write-Warn "Could not change power plan"
    }
    
    # Visual Effects
    if ($isAdmin) {
        Write-Info "Optimizing visual effects for performance..."
        try {
            $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
            Set-ItemProperty -Path $path -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
            Write-Success "Visual effects optimized"
        } catch {
            Write-Warn "Could not optimize visual effects"
        }
    }
    
    # Disable Transparency
    Write-Info "Disabling transparency effects..."
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0 -ErrorAction SilentlyContinue
        Write-Success "Transparency disabled"
    } catch {
        Write-Warn "Could not disable transparency"
    }
    
    # Disable animations
    Write-Info "Reducing animations..."
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -ErrorAction SilentlyContinue
        Write-Success "Animations reduced"
    } catch {
        Write-Warn "Could not reduce animations"
    }
    
    # Game Mode
    Write-Info "Enabling Game Mode..."
    try {
        $gamePath = "HKCU:\Software\Microsoft\GameBar"
        if (-not (Test-Path $gamePath)) { New-Item -Path $gamePath -Force | Out-Null }
        Set-ItemProperty -Path $gamePath -Name "AllowAutoGameMode" -Value 1 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $gamePath -Name "AutoGameModeEnabled" -Value 1 -ErrorAction SilentlyContinue
        Write-Success "Game Mode enabled"
    } catch {
        Write-Warn "Could not enable Game Mode"
    }
    
    # Disable Game Bar (ironically improves gaming perf)
    Write-Info "Disabling Game Bar overlay..."
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "UseNexusForGameBarEnabled" -Value 0 -ErrorAction SilentlyContinue
        Write-Success "Game Bar overlay disabled"
    } catch {
        Write-Warn "Could not disable Game Bar"
    }
    
    Write-Host ""
    Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host "  Performance optimizations applied!" -ForegroundColor Magenta
    Write-Host "  Some changes may require a restart to take full effect." -ForegroundColor DarkGray
    Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    
    Pause-Script
}

# ═══════════════════════════════════════════════════════════════════════════════
# NETWORK RESET
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-NetworkReset {
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Blue
    Write-Host "  │                    NETWORK RESET                            │" -ForegroundColor Blue
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Blue
    Write-Host ""
    
    # Flush DNS
    Write-Info "Flushing DNS cache..."
    try {
        ipconfig /flushdns | Out-Null
        Write-Success "DNS cache flushed"
    } catch {
        Write-Err "Could not flush DNS"
    }
    
    # Release/Renew IP (optional, can cause brief disconnect)
    Write-Info "Refreshing IP configuration..."
    try {
        ipconfig /release | Out-Null
        Start-Sleep -Seconds 2
        ipconfig /renew | Out-Null
        Write-Success "IP configuration refreshed"
    } catch {
        Write-Warn "Could not refresh IP (this is normal on some networks)"
    }
    
    if ($isAdmin) {
        # Reset Winsock
        Write-Info "Resetting Winsock catalog..."
        try {
            netsh winsock reset | Out-Null
            Write-Success "Winsock reset (restart required)"
        } catch {
            Write-Err "Could not reset Winsock"
        }
        
        # Reset TCP/IP
        Write-Info "Resetting TCP/IP stack..."
        try {
            netsh int ip reset | Out-Null
            Write-Success "TCP/IP stack reset (restart required)"
        } catch {
            Write-Err "Could not reset TCP/IP"
        }
    } else {
        Write-Warn "Skipping Winsock/TCP reset (requires Admin)"
    }
    
    # Clear ARP cache
    if ($isAdmin) {
        Write-Info "Clearing ARP cache..."
        try {
            netsh interface ip delete arpcache | Out-Null
            Write-Success "ARP cache cleared"
        } catch {
            Write-Warn "Could not clear ARP cache"
        }
    }
    
    Write-Host ""
    Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor Blue
    Write-Host "  Network reset complete!" -ForegroundColor Blue
    if ($isAdmin) {
        Write-Host "  A restart is recommended for full effect." -ForegroundColor DarkGray
    }
    Write-Host "  ══════════════════════════════════════════════════════════════" -ForegroundColor Blue
    
    Pause-Script
}

# ═══════════════════════════════════════════════════════════════════════════════
# DISK ANALYSIS
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-DiskAnalysis {
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor DarkYellow
    Write-Host "  │                    DISK ANALYSIS                            │" -ForegroundColor DarkYellow
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor DarkYellow
    Write-Host ""
    
    # Drive info
    Write-Info "Analyzing drives..."
    Write-Host ""
    
    Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $drive = $_.DeviceID
        $totalGB = [math]::Round($_.Size / 1GB, 2)
        $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
        $usedGB = $totalGB - $freeGB
        $percentUsed = [math]::Round(($usedGB / $totalGB) * 100, 0)
        
        $barWidth = 30
        $filledWidth = [math]::Floor($barWidth * $percentUsed / 100)
        $emptyWidth = $barWidth - $filledWidth
        
        $color = if ($percentUsed -gt 90) { "Red" } elseif ($percentUsed -gt 70) { "Yellow" } else { "Green" }
        
        Write-Host "  $drive " -NoNewline
        Write-Host "[" -NoNewline -ForegroundColor DarkGray
        Write-Host ("█" * $filledWidth) -NoNewline -ForegroundColor $color
        Write-Host ("░" * $emptyWidth) -NoNewline -ForegroundColor DarkGray
        Write-Host "] " -NoNewline -ForegroundColor DarkGray
        Write-Host "$percentUsed% " -NoNewline -ForegroundColor $color
        Write-Host "($freeGB GB free of $totalGB GB)" -ForegroundColor DarkGray
    }
    
    Write-Host ""
    Write-Info "Top 10 largest folders in your user profile:"
    Write-Host ""
    
    $userFolders = Get-ChildItem "$env:USERPROFILE" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $size = (Get-ChildItem $_.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1GB
        [PSCustomObject]@{
            Folder = $_.Name
            SizeGB = [math]::Round($size, 2)
        }
    } | Sort-Object SizeGB -Descending | Select-Object -First 10
    
    foreach ($folder in $userFolders) {
        $bar = "█" * [math]::Min([math]::Floor($folder.SizeGB), 20)
        $sizeStr = "{0,8:N2} GB" -f $folder.SizeGB
        $nameStr = "{0,-25}" -f $(if ($folder.Folder.Length -gt 25) { $folder.Folder.Substring(0,22) + "..." } else { $folder.Folder })
        Write-Host "    $nameStr $sizeStr " -NoNewline
        Write-Host $bar -ForegroundColor Cyan
    }
    
    Pause-Script
}

# ═══════════════════════════════════════════════════════════════════════════════
# FULL TUNE-UP
# ═══════════════════════════════════════════════════════════════════════════════

function Invoke-FullTuneUp {
    Write-Host ""
    Write-Host "  ┌─────────────────────────────────────────────────────────────┐" -ForegroundColor Red
    Write-Host "  │                    FULL TUNE-UP                             │" -ForegroundColor Red
    Write-Host "  └─────────────────────────────────────────────────────────────┘" -ForegroundColor Red
    Write-Host ""
    Write-Host "  This will run all optimizations. Continue? (Y/N): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host
    
    if ($confirm -eq "Y" -or $confirm -eq "y") {
        Write-Host ""
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "                         PHASE 1: CLEANUP" -ForegroundColor White
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Invoke-QuickClean
        
        Write-Host ""
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "                      PHASE 2: PERFORMANCE" -ForegroundColor White
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Invoke-PerformanceMode
        
        Write-Host ""
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Write-Host "                       PHASE 3: NETWORK" -ForegroundColor White
        Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Red
        Invoke-NetworkReset
        
        Write-Host ""
        Write-Host "  ╔═════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "  ║              FULL TUNE-UP COMPLETE!                         ║" -ForegroundColor Green
        Write-Host "  ║         Restart recommended for best results.              ║" -ForegroundColor Green
        Write-Host "  ╚═════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    }
    
    Pause-Script
}

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITIES
# ═══════════════════════════════════════════════════════════════════════════════

function Pause-Script {
    Write-Host ""
    Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN LOOP
# ═══════════════════════════════════════════════════════════════════════════════

do {
    Show-Banner
    Show-Menu
    $choice = Read-Host
    
    switch ($choice) {
        "1" { Invoke-QuickClean }
        "2" { Invoke-StartupManager }
        "3" { Invoke-PerformanceMode }
        "4" { Invoke-NetworkReset }
        "5" { Invoke-DiskAnalysis }
        "6" { Invoke-FullTuneUp }
        "0" { 
            Write-Host ""
            Write-Host "  Thanks for using PC Clean! Stay optimized. 🚀" -ForegroundColor Cyan
            Write-Host ""
            break 
        }
        default { 
            Write-Host ""
            Write-Warn "Invalid option. Please try again."
            Start-Sleep -Seconds 1
        }
    }
} while ($choice -ne "0")
