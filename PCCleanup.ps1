# ===============================================================================
# PC CLEAN - System Optimization Toolkit
# ===============================================================================
# WARNING:
# This script modifies system settings and deletes temporary files.
# Review the source code before running.
# Use at your own risk.
# ===============================================================================
# Version: 1.1
# License: MIT
# Repository: https://github.com/John-AI-Labs/pc-cleanup
# ===============================================================================

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ===============================================================================
# HELPER FUNCTIONS
# ===============================================================================

function Write-Success { param([string]$Text) Write-Host "  [+] $Text" -ForegroundColor Green }
function Write-Info { param([string]$Text) Write-Host "  [i] $Text" -ForegroundColor Cyan }
function Write-Warn { param([string]$Text) Write-Host "  [!] $Text" -ForegroundColor Yellow }
function Write-Err { param([string]$Text) Write-Host "  [x] $Text" -ForegroundColor Red }
function Write-Skip { param([string]$Text) Write-Host "  [-] $Text" -ForegroundColor DarkGray }

function Test-PendingReboot {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
    )
    foreach ($path in $paths) { 
        if (Test-Path $path) { return $true } 
    }
    return $false
}

function Test-BrowsersRunning {
    $browsers = @("chrome", "msedge", "firefox", "brave", "opera")
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $browsers -contains $_.Name }
    return $running
}

function Set-PowerPlanWithFallback {
    # High Performance GUID
    $highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    # Ultimate Performance GUID
    $ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    
    # Try High Performance first
    $result = powercfg /setactive $highPerfGuid 2>&1
    $currentPlan = powercfg /getactivescheme
    if ($currentPlan -match $highPerfGuid) {
        Write-Success "Power plan set to High Performance"
        return $true
    }
    
    # Try to unlock/duplicate Ultimate Performance
    Write-Info "High Performance unavailable, trying Ultimate Performance..."
    powercfg /duplicatescheme $ultimateGuid 2>&1 | Out-Null
    $result = powercfg /setactive $ultimateGuid 2>&1
    $currentPlan = powercfg /getactivescheme
    if ($currentPlan -match $ultimateGuid) {
        Write-Success "Power plan set to Ultimate Performance"
        return $true
    }
    
    # Both failed
    Write-Warn "Could not change power plan - your hardware may restrict this"
    return $false
}

# ===============================================================================
# ASCII ART BANNER
# ===============================================================================

function Show-Banner {
    Clear-Host
    
    Write-Host ""
    Write-Host "  ____   ____   ____ _     _____    _    _   _ " -ForegroundColor Cyan
    Write-Host " |  _ \ / ___| / ___| |   | ____|  / \  | \ | |" -ForegroundColor Cyan
    Write-Host " | |_) | |    | |   | |   |  _|   / _ \ |  \| |" -ForegroundColor Magenta
    Write-Host " |  __/| |___ | |___| |___| |___ / ___ \| |\  |" -ForegroundColor Magenta
    Write-Host " |_|    \____| \____|_____|_____/_/   \_\_| \_|" -ForegroundColor Blue
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor DarkGray
    Write-Host "    System Optimization Toolkit v1.1" -ForegroundColor White
    Write-Host "  ==============================================================" -ForegroundColor DarkGray
    Write-Host ""
    
    # Admin check
    if (-not $isAdmin) {
        Write-Warn "Running without Administrator privileges - some features limited"
        Write-Host "       Run as Administrator for full functionality" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    # Pending reboot check
    if (Test-PendingReboot) {
        Write-Host "  [!!] PENDING REBOOT DETECTED" -ForegroundColor Yellow
        Write-Host "       Windows has updates waiting. Restart for best results." -ForegroundColor DarkGray
        Write-Host ""
    }
}

# ===============================================================================
# MAIN MENU
# ===============================================================================

function Show-Menu {
    Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host "                         MAIN MENU                              " -ForegroundColor DarkCyan
    Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "   [1]  Quick Clean      - Temp files, cache, recycle bin" -ForegroundColor White
    Write-Host "   [2]  Startup Manager  - Disable bloat programs" -ForegroundColor White
    Write-Host "   [3]  Performance Mode - Optimize power and visuals" -ForegroundColor White
    Write-Host "   [4]  Network Reset    - Flush DNS, reset stack" -ForegroundColor White
    Write-Host "   [5]  Disk Analysis    - Show what is eating space" -ForegroundColor White
    Write-Host "   [6]  Full Tune-Up     - Run all optimizations (10-15 min)" -ForegroundColor White
    Write-Host ""
    Write-Host "   [0]  Exit" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Select an option: " -NoNewline -ForegroundColor Yellow
}

# ===============================================================================
# QUICK CLEAN
# ===============================================================================

function Invoke-QuickClean {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Green
    Write-Host "                        QUICK CLEAN                             " -ForegroundColor Green
    Write-Host "  ==============================================================" -ForegroundColor Green
    Write-Host ""
    
    $totalCleaned = 0
    
    # Check for running browsers
    $runningBrowsers = Test-BrowsersRunning
    if ($runningBrowsers) {
        $browserNames = ($runningBrowsers | Select-Object -Unique Name).Name -join ", "
        Write-Warn "Browsers running: $browserNames"
        Write-Host "       Close them for full cache cleaning" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    # Windows Temp
    Write-Info "Cleaning Windows Temp folder..."
    $tempPath = $env:TEMP
    try {
        $before = (Get-ChildItem $tempPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $before) { $before = 0 }
        Remove-Item "$tempPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        $after = (Get-ChildItem $tempPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $after) { $after = 0 }
        $cleaned = [math]::Round(($before - $after) / 1MB, 2)
        $totalCleaned += $cleaned
        Write-Success "Cleaned $cleaned MB from Temp"
    } catch {
        Write-Warn "Could not fully clean Temp folder"
    }
    
    # Windows Temp (System)
    Write-Info "Cleaning System Temp folder..."
    $sysTempPath = "C:\Windows\Temp"
    try {
        $before = (Get-ChildItem $sysTempPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $before) { $before = 0 }
        Remove-Item "$sysTempPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        $after = (Get-ChildItem $sysTempPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $after) { $after = 0 }
        $cleaned = [math]::Round(($before - $after) / 1MB, 2)
        $totalCleaned += $cleaned
        Write-Success "Cleaned $cleaned MB from System Temp"
    } catch {
        Write-Warn "Could not fully clean System Temp"
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
        if (-not ($runningBrowsers | Where-Object { $_.Name -eq "chrome" })) {
            try {
                $before = (Get-ChildItem $chromePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $before) { $before = 0 }
                Remove-Item "$chromePath\*" -Recurse -Force -ErrorAction SilentlyContinue
                $cleaned = [math]::Round($before / 1MB, 2)
                $totalCleaned += $cleaned
                Write-Success "Cleaned $cleaned MB from Chrome cache"
            } catch {
                Write-Warn "Could not clean Chrome cache"
            }
        } else {
            Write-Skip "Chrome cache skipped (browser running)"
        }
    }
    
    # Edge
    $edgePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
    if (Test-Path $edgePath) {
        if (-not ($runningBrowsers | Where-Object { $_.Name -eq "msedge" })) {
            try {
                $before = (Get-ChildItem $edgePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $before) { $before = 0 }
                Remove-Item "$edgePath\*" -Recurse -Force -ErrorAction SilentlyContinue
                $cleaned = [math]::Round($before / 1MB, 2)
                $totalCleaned += $cleaned
                Write-Success "Cleaned $cleaned MB from Edge cache"
            } catch {
                Write-Warn "Could not clean Edge cache"
            }
        } else {
            Write-Skip "Edge cache skipped (browser running)"
        }
    }
    
    # Firefox
    $firefoxPath = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $firefoxPath) {
        if (-not ($runningBrowsers | Where-Object { $_.Name -eq "firefox" })) {
            try {
                Get-ChildItem $firefoxPath -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                    $cachePath = Join-Path $_.FullName "cache2"
                    if (Test-Path $cachePath) {
                        Remove-Item "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                Write-Success "Cleaned Firefox cache"
            } catch {
                Write-Warn "Could not clean Firefox cache"
            }
        } else {
            Write-Skip "Firefox cache skipped (browser running)"
        }
    }
    
    # Windows Update Cache (Admin only)
    if ($isAdmin) {
        Write-Info "Cleaning Windows Update cache..."
        $wuPath = "C:\Windows\SoftwareDistribution\Download"
        if (Test-Path $wuPath) {
            try {
                $before = (Get-ChildItem $wuPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $before) { $before = 0 }
                Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
                Remove-Item "$wuPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                Start-Service wuauserv -ErrorAction SilentlyContinue
                $after = (Get-ChildItem $wuPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $after) { $after = 0 }
                $cleaned = [math]::Round(($before - $after) / 1MB, 2)
                $totalCleaned += $cleaned
                Write-Success "Cleaned $cleaned MB from Windows Update cache"
            } catch {
                Write-Warn "Could not clean Windows Update cache"
            }
        }
    } else {
        Write-Skip "Windows Update cache (requires Admin)"
    }
    
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Green
    $totalRounded = [math]::Round($totalCleaned, 2)
    Write-Host "  Total space recovered: $totalRounded MB" -ForegroundColor Green
    Write-Host "  ==============================================================" -ForegroundColor Green
    
    Pause-Script
}

# ===============================================================================
# STARTUP MANAGER
# ===============================================================================

function Invoke-StartupManager {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Yellow
    Write-Host "                      STARTUP MANAGER                           " -ForegroundColor Yellow
    Write-Host "  ==============================================================" -ForegroundColor Yellow
    Write-Host ""
    
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
            try {
                $items = Get-ItemProperty $path -ErrorAction SilentlyContinue
                $items.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                    $startupItems += [PSCustomObject]@{
                        Name = $_.Name
                        Path = $path
                        Command = $_.Value
                        Type = "Registry"
                    }
                }
            } catch {
                # Skip this path
            }
        }
    }
    
    # Startup folder
    $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
    if (Test-Path $startupFolder) {
        Get-ChildItem $startupFolder -ErrorAction SilentlyContinue | ForEach-Object {
            $startupItems += [PSCustomObject]@{
                Name = $_.BaseName
                Path = $_.FullName
                Command = $_.FullName
                Type = "Folder"
            }
        }
    }
    
    if ($startupItems.Count -eq 0) {
        Write-Info "No startup items found"
    } else {
        Write-Host "  Found $($startupItems.Count) startup items:" -ForegroundColor Cyan
        Write-Host ""
        
        $i = 1
        foreach ($item in $startupItems) {
            $displayName = $item.Name
            if ($displayName.Length -gt 40) { $displayName = $displayName.Substring(0, 37) + "..." }
            Write-Host "    [$i] $displayName" -ForegroundColor White
            $i++
        }
        
        Write-Host ""
        Write-Host "    [A] Disable common bloat automatically" -ForegroundColor Yellow
        Write-Host "    [0] Back to main menu" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Enter number to disable, A for auto-clean, or 0 to exit: " -NoNewline -ForegroundColor Yellow
        
        $choice = Read-Host
        
        if ($choice -eq "A" -or $choice -eq "a") {
            # Exact known bloat names (more precise than wildcards)
            $bloatNames = @(
                "OneDrive", "Spotify", "Discord", "Steam", "EpicGamesLauncher",
                "Origin", "Skype", "Teams", "iTunes", "iTunesHelper",
                "QuickTime", "Dropbox", "GoogleUpdate", "AdobeAAMUpdater",
                "CCleaner", "uTorrent", "BitTorrent", "Zoom"
            )
            
            $disabled = 0
            foreach ($item in $startupItems) {
                if ($bloatNames -contains $item.Name) {
                    try {
                        if ($item.Type -eq "Registry") {
                            Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction Stop
                        } else {
                            Remove-Item -Path $item.Path -Force -ErrorAction Stop
                        }
                        Write-Success "Disabled: $($item.Name)"
                        $disabled++
                    } catch {
                        Write-Err "Could not disable: $($item.Name)"
                    }
                }
            }
            
            if ($disabled -eq 0) {
                Write-Info "No common bloat found in startup"
            } else {
                Write-Host ""
                Write-Host "  Disabled $disabled startup items" -ForegroundColor Green
            }
        }
        elseif ($choice -match '^\d+$') {
            $index = [int]$choice - 1
            if ($index -ge 0 -and $index -lt $startupItems.Count) {
                $item = $startupItems[$index]
                try {
                    if ($item.Type -eq "Registry") {
                        Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction Stop
                    } else {
                        Remove-Item -Path $item.Path -Force -ErrorAction Stop
                    }
                    Write-Success "Disabled: $($item.Name)"
                } catch {
                    Write-Err "Could not disable: $($item.Name)"
                }
            }
        }
    }
    
    Pause-Script
}

# ===============================================================================
# PERFORMANCE MODE
# ===============================================================================

function Invoke-PerformanceMode {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Magenta
    Write-Host "                      PERFORMANCE MODE                          " -ForegroundColor Magenta
    Write-Host "  ==============================================================" -ForegroundColor Magenta
    Write-Host ""
    
    # Power Plan with fallback
    Write-Info "Setting power plan..."
    Set-PowerPlanWithFallback | Out-Null
    
    # Visual Effects
    Write-Info "Optimizing visual effects for performance..."
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (Test-Path $path) {
            Set-ItemProperty -Path $path -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
        }
        Write-Success "Visual effects optimized"
    } catch {
        Write-Warn "Could not optimize visual effects"
    }
    
    # Disable Transparency
    Write-Info "Disabling transparency effects..."
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (Test-Path $path) {
            Set-ItemProperty -Path $path -Name "EnableTransparency" -Value 0 -ErrorAction SilentlyContinue
        }
        Write-Success "Transparency disabled"
    } catch {
        Write-Warn "Could not disable transparency"
    }
    
    # Disable animations
    Write-Info "Reducing animations..."
    try {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue
        Write-Success "Menu delay reduced"
    } catch {
        Write-Warn "Could not reduce animations"
    }
    
    # Game Mode
    Write-Info "Enabling Game Mode..."
    try {
        $gamePath = "HKCU:\Software\Microsoft\GameBar"
        if (-not (Test-Path $gamePath)) { 
            New-Item -Path $gamePath -Force | Out-Null 
        }
        Set-ItemProperty -Path $gamePath -Name "AllowAutoGameMode" -Value 1 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $gamePath -Name "AutoGameModeEnabled" -Value 1 -ErrorAction SilentlyContinue
        Write-Success "Game Mode enabled"
    } catch {
        Write-Warn "Could not enable Game Mode"
    }
    
    # Disable Game Bar overlay
    Write-Info "Disabling Game Bar overlay..."
    try {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "UseNexusForGameBarEnabled" -Value 0 -ErrorAction SilentlyContinue
        Write-Success "Game Bar overlay disabled"
    } catch {
        Write-Warn "Could not disable Game Bar"
    }
    
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Magenta
    Write-Host "  Performance optimizations applied!" -ForegroundColor Magenta
    Write-Host "  Some changes may require a restart to take full effect." -ForegroundColor DarkGray
    Write-Host "  ==============================================================" -ForegroundColor Magenta
    
    Pause-Script
}

# ===============================================================================
# NETWORK RESET
# ===============================================================================

function Invoke-NetworkReset {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Blue
    Write-Host "                       NETWORK RESET                            " -ForegroundColor Blue
    Write-Host "  ==============================================================" -ForegroundColor Blue
    Write-Host ""
    
    # Flush DNS
    Write-Info "Flushing DNS cache..."
    try {
        $result = ipconfig /flushdns 2>&1
        Write-Success "DNS cache flushed"
    } catch {
        Write-Err "Could not flush DNS"
    }
    
    if ($isAdmin) {
        # Reset Winsock
        Write-Info "Resetting Winsock catalog..."
        try {
            $result = netsh winsock reset 2>&1
            Write-Success "Winsock reset (restart required)"
        } catch {
            Write-Err "Could not reset Winsock"
        }
        
        # Reset TCP/IP
        Write-Info "Resetting TCP/IP stack..."
        try {
            $result = netsh int ip reset 2>&1
            Write-Success "TCP/IP stack reset (restart required)"
        } catch {
            Write-Err "Could not reset TCP/IP"
        }
        
        # Clear ARP cache
        Write-Info "Clearing ARP cache..."
        try {
            $result = netsh interface ip delete arpcache 2>&1
            Write-Success "ARP cache cleared"
        } catch {
            Write-Warn "Could not clear ARP cache"
        }
    } else {
        Write-Skip "Winsock/TCP reset (requires Admin)"
    }
    
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Blue
    Write-Host "  Network reset complete!" -ForegroundColor Blue
    if ($isAdmin) {
        Write-Host "  A restart is recommended for full effect." -ForegroundColor DarkGray
    }
    Write-Host "  ==============================================================" -ForegroundColor Blue
    
    Pause-Script
}

# ===============================================================================
# DISK ANALYSIS
# ===============================================================================

function Invoke-DiskAnalysis {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor DarkYellow
    Write-Host "                       DISK ANALYSIS                            " -ForegroundColor DarkYellow
    Write-Host "  ==============================================================" -ForegroundColor DarkYellow
    Write-Host ""
    
    Write-Info "Analyzing drives..."
    Write-Host ""
    
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $drive = $_.DeviceID
        $totalGB = [math]::Round($_.Size / 1GB, 2)
        $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
        $usedGB = $totalGB - $freeGB
        $percentUsed = [math]::Round(($usedGB / $totalGB) * 100, 0)
        
        $barWidth = 30
        $filledWidth = [math]::Floor($barWidth * $percentUsed / 100)
        $emptyWidth = $barWidth - $filledWidth
        
        $barFilled = "#" * $filledWidth
        $barEmpty = "-" * $emptyWidth
        
        $color = "Green"
        if ($percentUsed -gt 90) { $color = "Red" }
        elseif ($percentUsed -gt 70) { $color = "Yellow" }
        
        Write-Host "  $drive " -NoNewline
        Write-Host "[" -NoNewline -ForegroundColor DarkGray
        Write-Host $barFilled -NoNewline -ForegroundColor $color
        Write-Host $barEmpty -NoNewline -ForegroundColor DarkGray
        Write-Host "] " -NoNewline -ForegroundColor DarkGray
        Write-Host "$percentUsed% " -NoNewline -ForegroundColor $color
        Write-Host "- $freeGB GB free" -ForegroundColor DarkGray
    }
    
    Write-Host ""
    Write-Info "Top 10 largest folders in your user profile..."
    Write-Host "       (scanning top-level only for speed)" -ForegroundColor DarkGray
    Write-Host ""
    
    $userFolders = Get-ChildItem $env:USERPROFILE -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $folderPath = $_.FullName
        $folderName = $_.Name
        $size = 0
        try {
            # Use -Depth 1 for speed
            $size = (Get-ChildItem $folderPath -Recurse -Depth 1 -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($null -eq $size) { $size = 0 }
        } catch {
            $size = 0
        }
        [PSCustomObject]@{
            Folder = $folderName
            SizeGB = [math]::Round($size / 1GB, 2)
        }
    } | Sort-Object SizeGB -Descending | Select-Object -First 10
    
    foreach ($folder in $userFolders) {
        $barLength = [math]::Min([math]::Floor($folder.SizeGB * 2), 20)
        $bar = "#" * $barLength
        $folderName = $folder.Folder
        if ($folderName.Length -gt 25) {
            $folderName = $folderName.Substring(0, 22) + "..."
        }
        $folderName = $folderName.PadRight(25)
        $sizeDisplay = $folder.SizeGB
        Write-Host "    $folderName " -NoNewline
        Write-Host "$sizeDisplay GB".PadLeft(10) -NoNewline
        Write-Host " $bar" -ForegroundColor Cyan
    }
    
    Pause-Script
}

# ===============================================================================
# DISM COMPONENT CLEANUP
# ===============================================================================

function Invoke-DISMCleanup {
    Write-Host ""
    Write-Info "Running DISM Component Cleanup (WinSxS)..."
    Write-Host "       This can take 5-15 minutes and may appear stuck at 10%." -ForegroundColor DarkGray
    Write-Host "       This is normal - do not close the window." -ForegroundColor DarkGray
    Write-Host ""
    
    try {
        $result = Dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
        Write-Success "DISM Component Cleanup complete"
    } catch {
        Write-Err "DISM cleanup failed"
    }
}

# ===============================================================================
# FULL TUNE-UP
# ===============================================================================

function Invoke-FullTuneUp {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Red
    Write-Host "                       FULL TUNE-UP                             " -ForegroundColor Red
    Write-Host "  ==============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "  This will run all optimizations including:" -ForegroundColor White
    Write-Host "    - Quick Clean (temp files, caches)" -ForegroundColor DarkGray
    Write-Host "    - Performance Mode (power plan, visuals)" -ForegroundColor DarkGray
    Write-Host "    - Network Reset (DNS, TCP/IP)" -ForegroundColor DarkGray
    Write-Host "    - Prefetch cleanup (Admin only)" -ForegroundColor DarkGray
    Write-Host "    - DISM Component Cleanup (5-15 min, Admin only)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Total time: 10-15 minutes" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Continue? (Y/N): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host
    
    if ($confirm -eq "Y" -or $confirm -eq "y") {
        Write-Host ""
        Write-Host "  ===================== PHASE 1: CLEANUP =======================" -ForegroundColor Red
        Invoke-QuickClean
        
        # Prefetch (Full Tune-Up only, Admin only)
        if ($isAdmin) {
            Write-Host ""
            Write-Info "Cleaning Prefetch..."
            $prefetchPath = "C:\Windows\Prefetch"
            try {
                $before = (Get-ChildItem $prefetchPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $before) { $before = 0 }
                Remove-Item "$prefetchPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                $after = (Get-ChildItem $prefetchPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $after) { $after = 0 }
                $cleaned = [math]::Round(($before - $after) / 1MB, 2)
                Write-Success "Cleaned $cleaned MB from Prefetch"
            } catch {
                Write-Warn "Could not clean Prefetch"
            }
        }
        
        Write-Host ""
        Write-Host "  =================== PHASE 2: PERFORMANCE ====================" -ForegroundColor Red
        Invoke-PerformanceMode
        
        Write-Host ""
        Write-Host "  ===================== PHASE 3: NETWORK ======================" -ForegroundColor Red
        Invoke-NetworkReset
        
        # DISM Cleanup (Admin only)
        if ($isAdmin) {
            Write-Host ""
            Write-Host "  ================= PHASE 4: DEEP CLEANUP ====================" -ForegroundColor Red
            Invoke-DISMCleanup
        }
        
        Write-Host ""
        Write-Host "  ==============================================================" -ForegroundColor Green
        Write-Host "                   FULL TUNE-UP COMPLETE!                       " -ForegroundColor Green
        Write-Host "           Restart recommended for best results.                " -ForegroundColor Green
        Write-Host "  ==============================================================" -ForegroundColor Green
    }
    
    Pause-Script
}

# ===============================================================================
# UTILITIES
# ===============================================================================

function Pause-Script {
    Write-Host ""
    Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ===============================================================================
# MAIN LOOP
# ===============================================================================

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
            Write-Host "  Thanks for using PC Clean." -ForegroundColor Cyan
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
