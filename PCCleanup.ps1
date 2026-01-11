# ===============================================================================
# PC CLEAN - System Optimization Toolkit
# ===============================================================================
#
# WHAT THIS SCRIPT DOES:
# This is a friendly PC maintenance tool that helps clean up junk files,
# speed up your computer, and fix common issues. Think of it like a
# digital spring cleaning for your Windows PC!
#
# IS IT SAFE?
# Yes! This script only removes temporary files that Windows creates
# automatically and can safely delete. It doesn't touch your personal
# files, photos, documents, or anything important. Before making any
# changes to settings, it offers to create a backup so you can undo
# everything if needed.
#
# ===============================================================================
# WARNING:
# This script modifies system settings and deletes temporary files.
# Review the source code before running.
# Use at your own risk.
# ===============================================================================
# Version: 1.2
# License: MIT
# Repository: https://github.com/bradley1320/pc-cleanup
# ===============================================================================

# ===============================================================================
# CHECKING IF WE HAVE PERMISSION TO DO EVERYTHING
# ===============================================================================
# 
# WHAT THIS DOES:
# Windows has two modes - regular user and "Administrator" (like a VIP pass).
# Some cleanup tasks need that VIP pass to work. This line checks which mode
# you're running in.
#
# WHY IT MATTERS:
# If you're NOT running as Administrator, you'll still get most features,
# but some deeper cleaning (like Windows Update cache) will be skipped.
# The script will tell you when something is skipped and why.
#
# HOW TO RUN AS ADMINISTRATOR:
# Right-click on PowerShell and choose "Run as Administrator"
#
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# ===============================================================================
# WHERE WE STORE YOUR BACKUPS
# ===============================================================================
#
# WHAT THIS DOES:
# This creates a path to a folder called "PCClean_Backup" in your user folder.
# For example: C:\Users\YourName\PCClean_Backup
#
# WHY WE DO THIS:
# Before we change any settings, we save your original settings here.
# If you don't like the changes, you can restore everything exactly
# how it was. Your backups are never deleted automatically - they're
# always there if you need them.
#
$backupPath = "$env:USERPROFILE\PCClean_Backup"

# ===============================================================================
# HELPER FUNCTIONS - PRETTY MESSAGES
# ===============================================================================
#
# WHAT THESE DO:
# These are just ways to show you colorful messages so you can easily
# see what's happening:
#   - Green [+] = Something worked! Success!
#   - Cyan [i] = Just letting you know something (information)
#   - Yellow [!] = Heads up! Something to be aware of (warning)
#   - Red [x] = Oops, something didn't work (error)
#   - Gray [-] = We skipped this step (usually because browser is open, etc.)
#
# DOES THIS CHANGE ANYTHING?
# No, these just control how text appears on screen. Purely cosmetic.
#

function Write-Success { param([string]$Text) Write-Host "  [+] $Text" -ForegroundColor Green }
function Write-Info { param([string]$Text) Write-Host "  [i] $Text" -ForegroundColor Cyan }
function Write-Warn { param([string]$Text) Write-Host "  [!] $Text" -ForegroundColor Yellow }
function Write-Err { param([string]$Text) Write-Host "  [x] $Text" -ForegroundColor Red }
function Write-Skip { param([string]$Text) Write-Host "  [-] $Text" -ForegroundColor DarkGray }

# ===============================================================================
# CHECK IF WINDOWS NEEDS A RESTART
# ===============================================================================
#
# WHAT THIS DOES:
# Windows sometimes installs updates in the background and needs a restart
# to finish. This function checks three places in the Windows Registry
# (like Windows' settings database) to see if a restart is waiting.
#
# WHY WE CHECK THIS:
# Running cleanup while updates are pending can sometimes cause issues.
# We just want to give you a heads-up if Windows is waiting for a restart.
#
# DOES THIS CHANGE ANYTHING?
# No! This only READS information - it doesn't change anything.
#

function Test-PendingReboot {
    # These are three places Windows stores "hey, I need a restart" flags
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
    )
    # Check each location - if any exist, a restart is pending
    foreach ($path in $paths) { 
        if (Test-Path $path) { return $true } 
    }
    return $false
}

# ===============================================================================
# CHECK IF ANY WEB BROWSERS ARE CURRENTLY OPEN
# ===============================================================================
#
# WHAT THIS DOES:
# Looks at all running programs to see if Chrome, Edge, Firefox, Brave,
# or Opera are currently open.
#
# WHY WE CHECK THIS:
# Browsers lock their cache files while they're running. If we try to
# delete cache files while the browser is open, it won't work. Rather
# than showing scary error messages, we just skip those caches and
# let you know why.
#
# DOES THIS CHANGE ANYTHING?
# No! This only looks at what's running - it doesn't close anything.
#

function Test-BrowsersRunning {
    # List of browser process names we look for
    $browsers = @("chrome", "msedge", "firefox", "brave", "opera")
    # Get all running processes and see if any match our browser list
    $running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $browsers -contains $_.Name }
    return $running
}

# ===============================================================================
# SWITCH TO A FASTER POWER PLAN
# ===============================================================================
#
# WHAT THIS DOES:
# Windows has different "power plans" that control how much power your PC uses.
# "Balanced" saves energy but can slow things down. "High Performance" uses
# more power but makes your PC faster. This function switches you to the
# faster option.
#
# âš¡ THIS CHANGES A SYSTEM SETTING:
# Your power plan will be changed to "High Performance" or "Ultimate Performance"
# This makes your PC prioritize speed over energy saving. Your electricity
# bill might go up slightly, and laptops will drain battery faster.
#
# CAN I UNDO THIS?
# Yes! The backup feature saves your original power plan, and you can also
# change it manually in Windows Settings > System > Power & sleep
#
# WHY THE "FALLBACK"?
# Not all computers have the same power plans available. Some laptops
# restrict which plans you can use. So we try the best option first,
# and if that doesn't work, we try alternatives.
#

function Set-PowerPlanWithFallback {
    # These are the unique IDs Windows uses for its built-in power plans
    # (Every Windows PC uses these same IDs - they're like serial numbers)
    $highPerfGuid = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
    $ultimateGuid = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    
    # Try to activate High Performance first
    $result = powercfg /setactive $highPerfGuid 2>&1
    $currentPlan = powercfg /getactivescheme
    if ($currentPlan -match $highPerfGuid) {
        Write-Success "Power plan set to High Performance"
        return $true
    }
    
    # If High Performance didn't work, try Ultimate Performance
    # (Ultimate Performance is even faster but uses more power)
    Write-Info "High Performance unavailable, trying Ultimate Performance..."
    # First create Ultimate Performance if it doesn't exist
    powercfg /duplicatescheme $ultimateGuid 2>&1 | Out-Null
    $result = powercfg /setactive $ultimateGuid 2>&1
    $currentPlan = powercfg /getactivescheme
    if ($currentPlan -match $ultimateGuid) {
        Write-Success "Power plan set to Ultimate Performance"
        return $true
    }
    
    # If nothing worked, the computer might have restrictions (common on laptops)
    Write-Warn "Could not change power plan - your hardware may restrict this"
    return $false
}

# ===============================================================================
# BACKUP YOUR SETTINGS
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# Creates a safety net by saving your current settings BEFORE we change
# anything. Think of it like taking a photo of how everything looks
# now, so we can put it back exactly the same later if needed.
#
# WHAT GETS BACKED UP:
# 1. Your current power plan (Balanced, High Performance, etc.)
# 2. Which programs start automatically when Windows boots
# 3. Your visual effects settings (animations, transparency, etc.)
#
# WHERE ARE BACKUPS STORED?
# In a folder called PCClean_Backup in your user folder.
# Example: C:\Users\YourName\PCClean_Backup
#
# HOW LONG ARE BACKUPS KEPT?
# Forever! We never delete old backups. You can manually delete them
# if you want to free up space (they're usually tiny - under 1MB).
#

function New-SettingsBackup {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor DarkCyan
    Write-Host "                     CREATING BACKUP                            " -ForegroundColor DarkCyan
    Write-Host "  ==============================================================" -ForegroundColor DarkCyan
    Write-Host ""
    
    # Create the backup folder if this is the first time running
    if (-not (Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        Write-Success "Created backup folder: $backupPath"
    }
    
    # Each backup gets a timestamp so you can have multiple backups
    # Format: backup_20240115_143022 (year-month-day_hour-minute-second)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFile = "$backupPath\backup_$timestamp"
    
    # -------------------------------------------------------------------------
    # BACKUP #1: POWER PLAN
    # -------------------------------------------------------------------------
    # We ask Windows "what power plan is currently active?" and save the answer.
    # Power plans have unique IDs (like "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c")
    # that we save to a text file.
    #
    Write-Info "Backing up power plan..."
    try {
        $currentPlan = powercfg /getactivescheme
        # Extract just the ID part (the long string of letters and numbers)
        if ($currentPlan -match '([a-f0-9-]{36})') {
            $Matches[1] | Out-File "$backupFile`_powerplan.txt" -Encoding UTF8
            Write-Success "Power plan backed up"
        }
    } catch {
        Write-Warn "Could not backup power plan"
    }
    
    # -------------------------------------------------------------------------
    # BACKUP #2: STARTUP PROGRAMS
    # -------------------------------------------------------------------------
    # Windows keeps a list of programs to launch at startup in the "Registry"
    # (Windows' settings database). We export this list to a file.
    # HKCU = "Current User" - just YOUR startup programs, not system-wide ones.
    #
    Write-Info "Backing up startup items..."
    try {
        $startupPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
        if (Test-Path $startupPath) {
            # Export the registry key to a .reg file (standard Windows format)
            reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" "$backupFile`_startup_hkcu.reg" /y 2>&1 | Out-Null
            Write-Success "User startup items backed up"
        }
    } catch {
        Write-Warn "Could not backup startup items"
    }
    
    # -------------------------------------------------------------------------
    # BACKUP #3: VISUAL SETTINGS
    # -------------------------------------------------------------------------
    # Windows has settings for animations, transparency, and other eye candy.
    # We save these so we can restore them if you prefer the fancier look.
    #
    Write-Info "Backing up visual settings..."
    try {
        # Visual effects setting (controls animations, shadows, etc.)
        $visualPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (Test-Path $visualPath) {
            $visualSetting = Get-ItemProperty -Path $visualPath -Name "VisualFXSetting" -ErrorAction SilentlyContinue
            if ($visualSetting) {
                $visualSetting.VisualFXSetting | Out-File "$backupFile`_visualfx.txt" -Encoding UTF8
            }
        }
        
        # Transparency setting (the see-through effect on windows and taskbar)
        $themePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (Test-Path $themePath) {
            $transSetting = Get-ItemProperty -Path $themePath -Name "EnableTransparency" -ErrorAction SilentlyContinue
            if ($transSetting) {
                $transSetting.EnableTransparency | Out-File "$backupFile`_transparency.txt" -Encoding UTF8
            }
        }
        Write-Success "Visual settings backed up"
    } catch {
        Write-Warn "Could not backup visual settings"
    }
    
    # Save which backup is the most recent (so restore knows where to look)
    $timestamp | Out-File "$backupPath\latest_backup.txt" -Encoding UTF8
    
    Write-Host ""
    Write-Success "Backup complete! Files saved to:"
    Write-Host "       $backupPath" -ForegroundColor DarkGray
    
    Pause-Script
}

# ===============================================================================
# RESTORE YOUR SETTINGS FROM BACKUP
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# This is the "undo button" - it takes the backup you created earlier
# and puts all your settings back exactly how they were.
#
# WHAT GETS RESTORED:
# 1. Your original power plan
# 2. Your original startup programs
# 3. Your original visual effects and transparency settings
#
# IS IT SAFE?
# Yes! It's just putting back settings you had before. Nothing new
# is being changed - we're restoring to a known good state.
#

function Restore-SettingsBackup {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor DarkYellow
    Write-Host "                    RESTORE BACKUP                              " -ForegroundColor DarkYellow
    Write-Host "  ==============================================================" -ForegroundColor DarkYellow
    Write-Host ""
    
    # Check if backup folder exists
    if (-not (Test-Path $backupPath)) {
        Write-Err "No backup folder found at $backupPath"
        Write-Info "Run a backup first before restoring."
        Pause-Script
        return
    }
    
    # Find the most recent backup
    $latestFile = "$backupPath\latest_backup.txt"
    if (-not (Test-Path $latestFile)) {
        Write-Err "No backup found. Run 'Create Backup' first."
        Pause-Script
        return
    }
    
    $latestTimestamp = Get-Content $latestFile -ErrorAction SilentlyContinue
    $backupFile = "$backupPath\backup_$latestTimestamp"
    
    # Show user what we're about to do and ask for confirmation
    # (We always ask before making changes - no surprises!)
    Write-Info "Found backup from: $latestTimestamp"
    Write-Host ""
    Write-Host "  This will restore:" -ForegroundColor White
    Write-Host "    - Power plan" -ForegroundColor DarkGray
    Write-Host "    - Startup items" -ForegroundColor DarkGray
    Write-Host "    - Visual settings" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Continue? (Y/N): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host
    
    # Only proceed if user explicitly says yes
    if ($confirm -ne "Y" -and $confirm -ne "y") {
        Write-Info "Restore cancelled."
        Pause-Script
        return
    }
    
    Write-Host ""
    
    # -------------------------------------------------------------------------
    # RESTORE #1: POWER PLAN
    # -------------------------------------------------------------------------
    # Read the saved power plan ID and tell Windows to switch back to it.
    #
    # âš¡ THIS CHANGES A SYSTEM SETTING:
    # Your power plan will be changed back to whatever it was before.
    #
    $powerFile = "$backupFile`_powerplan.txt"
    if (Test-Path $powerFile) {
        Write-Info "Restoring power plan..."
        try {
            $planGuid = Get-Content $powerFile -ErrorAction SilentlyContinue
            if ($planGuid) {
                powercfg /setactive $planGuid 2>&1 | Out-Null
                Write-Success "Power plan restored"
            }
        } catch {
            Write-Warn "Could not restore power plan"
        }
    }
    
    # -------------------------------------------------------------------------
    # RESTORE #2: STARTUP PROGRAMS
    # -------------------------------------------------------------------------
    # Import the .reg file back into Windows Registry.
    # This puts back any startup programs that were removed.
    #
    # âš¡ THIS CHANGES SYSTEM SETTINGS:
    # Programs that were disabled from startup will start again at boot.
    #
    $startupFile = "$backupFile`_startup_hkcu.reg"
    if (Test-Path $startupFile) {
        Write-Info "Restoring startup items..."
        try {
            reg import $startupFile 2>&1 | Out-Null
            Write-Success "Startup items restored"
        } catch {
            Write-Warn "Could not restore startup items"
        }
    }
    
    # -------------------------------------------------------------------------
    # RESTORE #3: VISUAL EFFECTS
    # -------------------------------------------------------------------------
    # Put back the animation and visual effects settings.
    #
    # âš¡ THIS CHANGES SYSTEM SETTINGS:
    # Your visual effects will return to their previous state (possibly
    # more animations and eye candy than the performance-optimized setting).
    #
    $visualFile = "$backupFile`_visualfx.txt"
    if (Test-Path $visualFile) {
        Write-Info "Restoring visual settings..."
        try {
            $visualSetting = Get-Content $visualFile -ErrorAction SilentlyContinue
            if ($visualSetting) {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value $visualSetting -ErrorAction SilentlyContinue
            }
            Write-Success "Visual effects restored"
        } catch {
            Write-Warn "Could not restore visual effects"
        }
    }
    
    # Restore transparency setting separately (it's stored in a different place)
    $transFile = "$backupFile`_transparency.txt"
    if (Test-Path $transFile) {
        try {
            $transSetting = Get-Content $transFile -ErrorAction SilentlyContinue
            if ($transSetting) {
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value $transSetting -ErrorAction SilentlyContinue
            }
            Write-Success "Transparency restored"
        } catch {
            Write-Warn "Could not restore transparency"
        }
    }
    
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Green
    Write-Host "  Restore complete! Some changes may require a restart." -ForegroundColor Green
    Write-Host "  ==============================================================" -ForegroundColor Green
    
    Pause-Script
}

# ===============================================================================
# CREATE A WINDOWS SYSTEM RESTORE POINT
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# Creates an official Windows "System Restore Point" - this is Windows'
# own undo feature that can roll back your entire system to this moment.
# It's like a save point in a video game.
#
# WHY THIS IS USEFUL:
# If something goes wrong (not just from this script, but anything),
# you can use Windows' built-in restore feature to go back in time.
#
# âš ï¸ REQUIRES ADMINISTRATOR:
# Only works if you ran PowerShell as Administrator.
#
# NOTE: Windows only allows one restore point per day to save disk space.
# If you already made one today, this might show a warning - that's okay!
#

function New-SystemRestorePoint {
    if (-not $isAdmin) {
        Write-Err "Creating restore points requires Administrator privileges"
        return $false
    }
    
    Write-Info "Creating Windows System Restore Point..."
    try {
        # Make sure System Restore is enabled for the C: drive
        Enable-ComputerRestore -Drive "C:\" -ErrorAction SilentlyContinue
        # Create the actual restore point with a description
        Checkpoint-Computer -Description "PC Clean - Before Optimization" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Success "System Restore Point created"
        return $true
    } catch {
        # This usually happens if you already made a restore point today
        Write-Warn "Could not create restore point (may already exist today)"
        return $false
    }
}

# ===============================================================================
# THE COOL BANNER YOU SEE AT THE TOP
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# Shows the fancy "PC CLEAN" logo when the script starts, along with
# helpful information like whether you're running as Admin and if
# Windows needs a restart.
#
# DOES THIS CHANGE ANYTHING?
# No! This is purely visual - just makes the tool look nice.
#

function Show-Banner {
    # Clear the screen for a fresh start
    Clear-Host
    
    # ASCII art logo - just for fun!
    Write-Host ""
    Write-Host "  ____   ____   ____ _     _____    _    _   _ " -ForegroundColor Cyan
    Write-Host " |  _ \ / ___| / ___| |   | ____|  / \  | \ | |" -ForegroundColor Cyan
    Write-Host " | |_) | |    | |   | |   |  _|   / _ \ |  \| |" -ForegroundColor Magenta
    Write-Host " |  __/| |___ | |___| |___| |___ / ___ \| |\  |" -ForegroundColor Magenta
    Write-Host " |_|    \____| \____|_____|_____/_/   \_\_| \_|" -ForegroundColor Blue
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor DarkGray
    Write-Host "    System Optimization Toolkit v1.2" -ForegroundColor White
    Write-Host "  ==============================================================" -ForegroundColor DarkGray
    Write-Host ""
    
    # Let users know if they're not running as Admin (some features limited)
    if (-not $isAdmin) {
        Write-Warn "Running without Administrator privileges - some features limited"
        Write-Host "       Run as Administrator for full functionality" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    # Heads up if Windows is waiting for a restart
    if (Test-PendingReboot) {
        Write-Host "  [!!] PENDING REBOOT DETECTED" -ForegroundColor Yellow
        Write-Host "       Windows has updates waiting. Restart for best results." -ForegroundColor DarkGray
        Write-Host ""
    }
    
    # Let users know they have a backup available if they do
    if (Test-Path "$backupPath\latest_backup.txt") {
        Write-Host "  [i] Backup available for restore" -ForegroundColor DarkGray
        Write-Host ""
    }
}

# ===============================================================================
# THE MAIN MENU
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# Shows you all the options available. Each option is explained in its
# own section below.
#
# DOES THIS CHANGE ANYTHING?
# No! Just displays the menu. You choose what happens next.
#

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
    Write-Host "   [7]  Create Backup    - Save current settings" -ForegroundColor DarkGreen
    Write-Host "   [8]  Restore Backup   - Revert to saved settings" -ForegroundColor DarkYellow
    Write-Host ""
    Write-Host "   [0]  Exit" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Select an option: " -NoNewline -ForegroundColor Yellow
}

# ===============================================================================
# QUICK CLEAN - DELETE TEMPORARY FILES
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# Deletes "junk" files that Windows and your programs create temporarily.
# These files are safe to delete and often pile up, taking space and
# sometimes slowing things down.
#
# WHAT GETS DELETED:
# 1. Your user Temp folder - random temporary files from programs
# 2. Windows' system Temp folder - same thing, but system-wide
# 3. Recycle Bin - stuff you already deleted (just emptying it)
# 4. Browser caches - saved copies of websites (Chrome, Edge, Firefox)
# 5. Windows Update cache - old update files that already installed
#
# IS THIS SAFE?
# Yes! These are all designed to be deleted. Windows and programs will
# recreate them as needed. Browsers rebuild their cache automatically
# (websites might load slightly slower the first time after cleaning).
#
# âš ï¸ YOUR PERSONAL FILES ARE NEVER TOUCHED:
# Documents, photos, downloads - everything you care about is safe.
# We only delete files in designated "temporary" locations.
#

function Invoke-QuickClean {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Green
    Write-Host "                        QUICK CLEAN                             " -ForegroundColor Green
    Write-Host "  ==============================================================" -ForegroundColor Green
    Write-Host ""
    
    # Keep track of how much space we free up (to show you at the end)
    $totalCleaned = 0
    
    # -------------------------------------------------------------------------
    # BROWSER CHECK
    # -------------------------------------------------------------------------
    # See if any browsers are running - we can't clean their cache if they are.
    # This is just a heads-up, not an error.
    #
    $runningBrowsers = Test-BrowsersRunning
    if ($runningBrowsers) {
        $browserNames = ($runningBrowsers | Select-Object -Unique Name).Name -join ", "
        Write-Warn "Browsers running: $browserNames"
        Write-Host "       Close them for full cache cleaning" -ForegroundColor DarkGray
        Write-Host ""
    }
    
    # -------------------------------------------------------------------------
    # CLEAN USER TEMP FOLDER
    # -------------------------------------------------------------------------
    # Location: Usually C:\Users\YourName\AppData\Local\Temp
    # Contains: Random files programs create while running
    # Safe to delete: YES - programs recreate what they need
    #
    Write-Info "Cleaning Windows Temp folder..."
    $tempPath = $env:TEMP
    try {
        # Measure how big it is BEFORE cleaning
        $before = (Get-ChildItem $tempPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $before) { $before = 0 }
        
        # Delete everything in the Temp folder
        # -Force: Don't ask "are you sure?" for each file
        # -ErrorAction SilentlyContinue: Skip files that are currently in use
        Remove-Item "$tempPath\*" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Measure how big it is AFTER cleaning
        $after = (Get-ChildItem $tempPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $after) { $after = 0 }
        
        # Calculate how much we freed up
        $cleaned = [math]::Round(($before - $after) / 1MB, 2)
        $totalCleaned += $cleaned
        Write-Success "Cleaned $cleaned MB from Temp"
    } catch {
        Write-Warn "Could not fully clean Temp folder"
    }
    
    # -------------------------------------------------------------------------
    # CLEAN SYSTEM TEMP FOLDER
    # -------------------------------------------------------------------------
    # Location: C:\Windows\Temp
    # Contains: System-wide temporary files
    # Safe to delete: YES - same as user Temp, just system-wide
    #
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
    
    # -------------------------------------------------------------------------
    # EMPTY RECYCLE BIN
    # -------------------------------------------------------------------------
    # What this does: Permanently deletes files you already put in the trash
    # Safe: YES - you already deleted these, we're just finishing the job
    #
    Write-Info "Emptying Recycle Bin..."
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Write-Success "Recycle Bin emptied"
    } catch {
        Write-Warn "Could not empty Recycle Bin"
    }
    
    # -------------------------------------------------------------------------
    # CLEAN BROWSER CACHES
    # -------------------------------------------------------------------------
    # What these are: Browsers save copies of websites so pages load faster
    # Safe to delete: YES - browsers rebuild this automatically
    # Side effect: Websites may load slightly slower the first time you visit
    #
    Write-Info "Cleaning browser caches..."
    
    # ----- GOOGLE CHROME -----
    $chromePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
    if (Test-Path $chromePath) {
        # Only clean if Chrome is NOT running (files would be locked)
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
    
    # ----- MICROSOFT EDGE -----
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
    
    # ----- MOZILLA FIREFOX -----
    # Firefox stores profiles differently - each user can have multiple profiles
    $firefoxPath = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $firefoxPath) {
        if (-not ($runningBrowsers | Where-Object { $_.Name -eq "firefox" })) {
            try {
                # Loop through each Firefox profile and clean its cache
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
    
    # -------------------------------------------------------------------------
    # CLEAN WINDOWS UPDATE CACHE
    # -------------------------------------------------------------------------
    # Location: C:\Windows\SoftwareDistribution\Download
    # Contains: Downloaded Windows updates that have already been installed
    # Safe to delete: YES - these are just leftover installation files
    #
    # âš ï¸ REQUIRES ADMINISTRATOR:
    # This folder is protected, so we need Admin rights to clean it.
    # We also need to temporarily stop the Windows Update service.
    #
    if ($isAdmin) {
        Write-Info "Cleaning Windows Update cache..."
        $wuPath = "C:\Windows\SoftwareDistribution\Download"
        if (Test-Path $wuPath) {
            try {
                $before = (Get-ChildItem $wuPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                if ($null -eq $before) { $before = 0 }
                
                # Stop Windows Update service so we can delete the files
                Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
                Remove-Item "$wuPath\*" -Recurse -Force -ErrorAction SilentlyContinue
                # Start it back up - Windows Update will work normally
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
    
    # Show the total space recovered
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Green
    $totalRounded = [math]::Round($totalCleaned, 2)
    Write-Host "  Total space recovered: $totalRounded MB" -ForegroundColor Green
    Write-Host "  ==============================================================" -ForegroundColor Green
    
    Pause-Script
}

# ===============================================================================
# STARTUP MANAGER - CONTROL WHAT RUNS AT BOOT
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# Shows you all the programs that automatically start when Windows boots,
# and lets you disable the ones you don't need. Fewer startup programs
# means faster boot times and less stuff running in the background.
#
# IS THIS SAFE?
# Yes! Disabling a startup program doesn't uninstall it - the program
# still works fine, it just won't start automatically. You can always
# open it manually when you need it.
#
# WHAT'S "BLOAT"?
# Programs like Spotify, Discord, Steam, etc. that add themselves to
# startup so they're ready when you log in. Nice if you use them
# immediately, but wasteful if you don't need them right away.
#
# âš¡ THIS CAN CHANGE SYSTEM SETTINGS:
# If you choose to disable programs, they won't start automatically
# anymore. You can re-enable them in Windows Task Manager (Startup tab)
# or restore from backup.
#

function Invoke-StartupManager {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Yellow
    Write-Host "                      STARTUP MANAGER                           " -ForegroundColor Yellow
    Write-Host "  ==============================================================" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Info "Scanning startup programs..."
    Write-Host ""
    
    # We'll collect all startup items into this list
    $startupItems = @()
    
    # -------------------------------------------------------------------------
    # SCAN REGISTRY FOR STARTUP PROGRAMS
    # -------------------------------------------------------------------------
    # Windows stores startup programs in two places in the Registry:
    # - HKCU (Current User) - just for your account
    # - HKLM (Local Machine) - for all users on this PC
    #
    $regPaths = @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run"
    )
    
    foreach ($path in $regPaths) {
        if (Test-Path $path) {
            try {
                $items = Get-ItemProperty $path -ErrorAction SilentlyContinue
                # Get each program entry (filter out PowerShell's own properties)
                $items.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" } | ForEach-Object {
                    $startupItems += [PSCustomObject]@{
                        Name = $_.Name
                        Path = $path
                        Command = $_.Value
                        Type = "Registry"
                    }
                }
            } catch { }
        }
    }
    
    # -------------------------------------------------------------------------
    # SCAN STARTUP FOLDER
    # -------------------------------------------------------------------------
    # Some programs put shortcuts in a special "Startup" folder instead
    # of using the Registry. We check there too.
    #
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
    
    # Show what we found
    if ($startupItems.Count -eq 0) {
        Write-Info "No startup items found"
    } else {
        Write-Host "  Found $($startupItems.Count) startup items:" -ForegroundColor Cyan
        Write-Host ""
        
        # List all programs with numbers so user can choose
        $i = 1
        foreach ($item in $startupItems) {
            $displayName = $item.Name
            # Truncate long names so the display stays neat
            if ($displayName.Length -gt 40) { $displayName = $displayName.Substring(0, 37) + "..." }
            Write-Host "    [$i] $displayName" -ForegroundColor White
            $i++
        }
        
        Write-Host ""
        Write-Host "    [A] Disable common bloat automatically" -ForegroundColor Yellow
        Write-Host "    [0] Back to main menu" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Enter numbers to disable (e.g., 1,3,5), A for auto-clean, or 0 to exit: " -NoNewline -ForegroundColor Yellow
        
        $choice = Read-Host
        
        # ---------------------------------------------------------------------
        # OPTION A: AUTO-DISABLE COMMON BLOAT
        # ---------------------------------------------------------------------
        # We have a list of programs that most people don't need at startup.
        # These are safe to disable - the programs still work, they just
        # won't start automatically.
        #
        if ($choice -eq "A" -or $choice -eq "a") {
            # Programs that commonly add themselves to startup unnecessarily
            $bloatNames = @(
                "OneDrive", "Spotify", "Discord", "Steam", "EpicGamesLauncher",
                "Origin", "Skype", "Teams", "iTunes", "iTunesHelper",
                "QuickTime", "Dropbox", "GoogleUpdate", "AdobeAAMUpdater",
                "CCleaner", "uTorrent", "BitTorrent", "Zoom"
            )
            
            $disabled = 0
            foreach ($item in $startupItems) {
                # Check if this program is in our "bloat" list
                if ($bloatNames -contains $item.Name) {
                    try {
                        # How we disable depends on where the startup entry lives
                        if ($item.Type -eq "Registry") {
                            # Remove the Registry entry
                            Remove-ItemProperty -Path $item.Path -Name $item.Name -ErrorAction Stop
                        } else {
                            # Delete the shortcut from Startup folder
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
        # ---------------------------------------------------------------------
        # OPTION: DISABLE SPECIFIC PROGRAM(S) BY NUMBER
        # ---------------------------------------------------------------------
        # Supports multiple selections like "1,3,5" or single "1"
        #
        elseif ($choice -match '^[\d,\s]+$') {
            # Split by comma, trim whitespace, remove empty entries
            $selections = $choice -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            $disabled = 0
            
            foreach ($selection in $selections) {
                if ($selection -match '^\d+$') {
                    $index = [int]$selection - 1
                    if ($index -ge 0 -and $index -lt $startupItems.Count) {
                        $item = $startupItems[$index]
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
                    } else {
                        Write-Warn "Invalid selection: $selection"
                    }
                }
            }
            
            if ($disabled -gt 0) {
                Write-Host ""
                Write-Host "  Disabled $disabled startup item(s)" -ForegroundColor Green
            }
        }
    }
    
    Pause-Script
}

# ===============================================================================
# PERFORMANCE MODE - OPTIMIZE FOR SPEED
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# Adjusts Windows settings to prioritize speed over visual prettiness.
# This can make older PCs feel snappier and helps gaming performance.
#
# âš¡ THIS CHANGES MULTIPLE SYSTEM SETTINGS:
# 1. Power Plan â†’ High Performance (more power, faster CPU)
# 2. Visual Effects â†’ Performance mode (less animations)
# 3. Transparency â†’ Disabled (no see-through windows)
# 4. Menu Delay â†’ Instant (menus appear immediately)
# 5. Game Mode â†’ Enabled (Windows prioritizes games)
# 6. Game Bar â†’ Disabled (removes overlay that can cause stuttering)
#
# CAN I UNDO THIS?
# Yes! Use the Restore Backup option to put everything back.
# You can also manually change these in Windows Settings.
#
# WILL MY PC LOOK DIFFERENT?
# A little. Windows will look a bit more "basic" - less smooth
# animations, no transparency effects. But it will feel faster!
#

function Invoke-PerformanceMode {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Magenta
    Write-Host "                      PERFORMANCE MODE                          " -ForegroundColor Magenta
    Write-Host "  ==============================================================" -ForegroundColor Magenta
    Write-Host ""
    
    # -------------------------------------------------------------------------
    # CHANGE #1: POWER PLAN
    # -------------------------------------------------------------------------
    # Switches from "Balanced" to "High Performance"
    # This tells Windows to run your CPU at higher speeds more often.
    #
    Write-Info "Setting power plan..."
    Set-PowerPlanWithFallback | Out-Null
    
    # -------------------------------------------------------------------------
    # CHANGE #2: VISUAL EFFECTS
    # -------------------------------------------------------------------------
    # Setting this to "2" tells Windows to "Adjust for best performance"
    # This disables fancy animations like window minimize/maximize effects,
    # smooth scrolling, and fading menus.
    #
    Write-Info "Optimizing visual effects for performance..."
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (Test-Path $path) {
            # Value 2 = "Adjust for best performance" in Windows settings
            Set-ItemProperty -Path $path -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
        }
        Write-Success "Visual effects optimized"
    } catch {
        Write-Warn "Could not optimize visual effects"
    }
    
    # -------------------------------------------------------------------------
    # CHANGE #3: TRANSPARENCY
    # -------------------------------------------------------------------------
    # Disables the see-through effect on windows, taskbar, and Start menu.
    # This effect uses GPU power that could go to other things.
    #
    Write-Info "Disabling transparency effects..."
    try {
        $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        if (Test-Path $path) {
            # Value 0 = transparency OFF
            Set-ItemProperty -Path $path -Name "EnableTransparency" -Value 0 -ErrorAction SilentlyContinue
        }
        Write-Success "Transparency disabled"
    } catch {
        Write-Warn "Could not disable transparency"
    }
    
    # -------------------------------------------------------------------------
    # CHANGE #4: MENU DELAY
    # -------------------------------------------------------------------------
    # Windows normally waits a fraction of a second before showing menus.
    # Setting this to 0 makes menus appear instantly.
    #
    Write-Info "Reducing animations..."
    try {
        # Value "0" = no delay, menus appear instantly
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue
        Write-Success "Menu delay reduced"
    } catch {
        Write-Warn "Could not reduce animations"
    }
    
    # -------------------------------------------------------------------------
    # CHANGE #5: GAME MODE
    # -------------------------------------------------------------------------
    # Game Mode is a Windows feature that prioritizes games when they're
    # running. It reduces background activity and can improve FPS.
    #
    Write-Info "Enabling Game Mode..."
    try {
        $gamePath = "HKCU:\Software\Microsoft\GameBar"
        # Create the registry key if it doesn't exist
        if (-not (Test-Path $gamePath)) { 
            New-Item -Path $gamePath -Force | Out-Null 
        }
        # Enable Game Mode
        Set-ItemProperty -Path $gamePath -Name "AllowAutoGameMode" -Value 1 -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $gamePath -Name "AutoGameModeEnabled" -Value 1 -ErrorAction SilentlyContinue
        Write-Success "Game Mode enabled"
    } catch {
        Write-Warn "Could not enable Game Mode"
    }
    
    # -------------------------------------------------------------------------
    # CHANGE #6: GAME BAR OVERLAY
    # -------------------------------------------------------------------------
    # The Game Bar is an overlay that lets you record clips and take screenshots.
    # But it can cause stuttering in some games. Disabling it removes
    # the overlay but you can still use Win+G to open it if needed.
    #
    Write-Info "Disabling Game Bar overlay..."
    try {
        # Value 0 = don't show Game Bar overlay in games
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
# NETWORK RESET - FIX INTERNET ISSUES
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# Clears out network caches and resets network settings to their defaults.
# This can fix many common internet problems like slow connections,
# websites not loading, or "can connect to WiFi but no internet."
#
# WHAT GETS RESET:
# 1. DNS Cache - stored website addresses (like a phone book for the internet)
# 2. Winsock - the Windows networking component (Admin only)
# 3. TCP/IP Stack - core internet protocols (Admin only)
# 4. ARP Cache - stored device addresses on your network (Admin only)
#
# IS THIS SAFE?
# Yes! These are all "soft resets" - your WiFi passwords, network settings,
# and configured connections are NOT affected. We're just clearing
# temporary caches that can sometimes get corrupted.
#
# âš ï¸ SOME CHANGES REQUIRE A RESTART:
# The Winsock and TCP/IP resets take effect after you restart Windows.
#

function Invoke-NetworkReset {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor Blue
    Write-Host "                       NETWORK RESET                            " -ForegroundColor Blue
    Write-Host "  ==============================================================" -ForegroundColor Blue
    Write-Host ""
    
    # -------------------------------------------------------------------------
    # RESET #1: DNS CACHE
    # -------------------------------------------------------------------------
    # DNS is like a phone book - it translates "google.com" to an IP address.
    # Windows caches these lookups. Sometimes the cache gets stale or corrupt.
    # Flushing it forces fresh lookups.
    #
    # This is safe and doesn't require admin - anyone can do it.
    #
    Write-Info "Flushing DNS cache..."
    try {
        $result = ipconfig /flushdns 2>&1
        Write-Success "DNS cache flushed"
    } catch {
        Write-Err "Could not flush DNS"
    }
    
    # The following resets require Administrator privileges
    if ($isAdmin) {
        # ---------------------------------------------------------------------
        # RESET #2: WINSOCK
        # ---------------------------------------------------------------------
        # Winsock is the Windows component that handles network connections.
        # "Resetting" it restores it to default state, fixing corruption.
        #
        # âš¡ THIS CHANGES SYSTEM SETTINGS (requires restart):
        # Some third-party software (VPNs, firewalls) may need to be
        # reconfigured after this, but it's rare.
        #
        Write-Info "Resetting Winsock catalog..."
        try {
            $result = netsh winsock reset 2>&1
            Write-Success "Winsock reset (restart required)"
        } catch {
            Write-Err "Could not reset Winsock"
        }
        
        # ---------------------------------------------------------------------
        # RESET #3: TCP/IP STACK
        # ---------------------------------------------------------------------
        # TCP/IP is the core protocol that makes the internet work.
        # This reset clears any custom settings and restores defaults.
        #
        # âš¡ THIS CHANGES SYSTEM SETTINGS (requires restart):
        # If you had custom TCP/IP settings (rare), they'll be reset.
        #
        Write-Info "Resetting TCP/IP stack..."
        try {
            $result = netsh int ip reset 2>&1
            Write-Success "TCP/IP stack reset (restart required)"
        } catch {
            Write-Err "Could not reset TCP/IP"
        }
        
        # ---------------------------------------------------------------------
        # RESET #4: ARP CACHE
        # ---------------------------------------------------------------------
        # ARP maps IP addresses to device hardware addresses on your network.
        # Clearing this cache can fix issues with connecting to local devices.
        #
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
# DISK ANALYSIS - SEE WHAT'S USING YOUR SPACE
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# Shows you a visual breakdown of your disk space and which folders
# are taking up the most room. Helps you find what to delete if you're
# running low on space.
#
# DOES THIS CHANGE ANYTHING?
# No! This is read-only - it just looks at folder sizes and shows you
# the information. Nothing is deleted or modified.
#
# WHY ONLY TOP-LEVEL FOLDERS?
# Scanning every single file on your disk could take a very long time.
# We scan one level deep for speed - this usually shows you the big
# culprits (like Downloads, AppData, Games folders).
#

function Invoke-DiskAnalysis {
    Write-Host ""
    Write-Host "  ==============================================================" -ForegroundColor DarkYellow
    Write-Host "                       DISK ANALYSIS                            " -ForegroundColor DarkYellow
    Write-Host "  ==============================================================" -ForegroundColor DarkYellow
    Write-Host ""
    
    Write-Info "Analyzing drives..."
    Write-Host ""
    
    # -------------------------------------------------------------------------
    # SHOW DRIVE SPACE
    # -------------------------------------------------------------------------
    # Get all local drives (DriveType=3 means fixed hard drives, not USB/CD)
    # and show a visual bar of how full each one is.
    #
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
        $drive = $_.DeviceID
        $totalGB = [math]::Round($_.Size / 1GB, 2)
        $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
        $usedGB = $totalGB - $freeGB
        $percentUsed = [math]::Round(($usedGB / $totalGB) * 100, 0)
        
        # Create a visual progress bar
        $barWidth = 30
        $filledWidth = [math]::Floor($barWidth * $percentUsed / 100)
        $emptyWidth = $barWidth - $filledWidth
        
        $barFilled = "#" * $filledWidth
        $barEmpty = "-" * $emptyWidth
        
        # Color code: green = good, yellow = getting full, red = almost full
        $color = "Green"
        if ($percentUsed -gt 90) { $color = "Red" }
        elseif ($percentUsed -gt 70) { $color = "Yellow" }
        
        # Display the bar
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
    
    # -------------------------------------------------------------------------
    # SHOW LARGEST FOLDERS
    # -------------------------------------------------------------------------
    # Scan your user folder and find the biggest space hogs.
    # Common culprits: Downloads, AppData, Games, Videos
    #
    $userFolders = Get-ChildItem $env:USERPROFILE -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $folderPath = $_.FullName
        $folderName = $_.Name
        $size = 0
        try {
            # Only scan 1 level deep for speed (Depth 1)
            $size = (Get-ChildItem $folderPath -Recurse -Depth 1 -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
            if ($null -eq $size) { $size = 0 }
        } catch {
            $size = 0
        }
        # Return an object with the folder name and size
        [PSCustomObject]@{
            Folder = $folderName
            SizeGB = [math]::Round($size / 1GB, 2)
        }
    } | Sort-Object SizeGB -Descending | Select-Object -First 10
    
    # Display the results with visual bars
    foreach ($folder in $userFolders) {
        $barLength = [math]::Min([math]::Floor($folder.SizeGB * 2), 20)
        $bar = "#" * $barLength
        $folderName = $folder.Folder
        # Truncate long folder names
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
# DISM COMPONENT CLEANUP - DEEP WINDOWS CLEANUP
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# Uses Windows' built-in DISM tool to clean up the "Component Store"
# (also called WinSxS). This is where Windows keeps backup copies of
# system files. Over time, this folder can grow quite large.
#
# IS THIS SAFE?
# Yes! DISM is Microsoft's official tool and only removes files that
# Windows determines are safe to delete (old versions of updated
# components that can't be uninstalled anymore).
#
# âš ï¸ THIS TAKES A LONG TIME:
# 5-15 minutes is normal, and it may appear "stuck" at 10% for a while.
# This is completely normal - don't close the window! The tool is
# analyzing which files are safe to remove.
#
# âš ï¸ REQUIRES ADMINISTRATOR
#

function Invoke-DISMCleanup {
    Write-Host ""
    Write-Info "Running DISM Component Cleanup (WinSxS)..."
    Write-Host "       This can take 5-15 minutes and may appear stuck at 10%." -ForegroundColor DarkGray
    Write-Host "       This is normal - do not close the window." -ForegroundColor DarkGray
    Write-Host ""
    
    try {
        # Run the official Microsoft DISM tool
        # /Online = work on the running Windows installation
        # /Cleanup-Image = we're cleaning up, not repairing
        # /StartComponentCleanup = remove superseded components
        $result = Dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1
        Write-Success "DISM Component Cleanup complete"
    } catch {
        Write-Err "DISM cleanup failed"
    }
}

# ===============================================================================
# FULL TUNE-UP - THE WHOLE SHEBANG
# ===============================================================================
#
# WHAT THIS FUNCTION DOES:
# Runs ALL the optimizations in one go:
# 1. Quick Clean (temp files, caches, recycle bin)
# 2. Performance Mode (power plan, visual effects)
# 3. Network Reset (DNS, TCP/IP)
# 4. Prefetch cleanup (Admin only)
# 5. DISM Component Cleanup (Admin only)
#
# â±ï¸ HOW LONG DOES IT TAKE?
# About 10-15 minutes, depending on your system. The DISM cleanup
# at the end takes the longest.
#
# âš¡ THIS CHANGES MULTIPLE SYSTEM SETTINGS:
# Same changes as Performance Mode, plus file deletions from Quick Clean.
# A backup is created AUTOMATICALLY before any changes are made.
#
# âš ï¸ RESTART RECOMMENDED:
# For best results, restart your computer after this completes.
#

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
    
    # Offer to create a Windows System Restore Point (the ultimate safety net)
    if ($isAdmin) {
        Write-Host "  Create System Restore Point first? (Y/N): " -NoNewline -ForegroundColor Cyan
        $restoreChoice = Read-Host
        if ($restoreChoice -eq "Y" -or $restoreChoice -eq "y") {
            New-SystemRestorePoint
        }
        Write-Host ""
    }
    
    # Confirm before proceeding
    Write-Host "  Continue with Full Tune-Up? (Y/N): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host
    
    if ($confirm -eq "Y" -or $confirm -eq "y") {
        # ---------------------------------------------------------------------
        # AUTOMATIC BACKUP
        # ---------------------------------------------------------------------
        # We ALWAYS create a backup before making changes.
        # This way you can undo everything even if you didn't manually backup.
        #
        Write-Host ""
        Write-Info "Auto-creating settings backup..."
        if (-not (Test-Path $backupPath)) {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
        }
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFile = "$backupPath\backup_$timestamp"
        
        try {
            # Save current power plan
            $currentPlan = powercfg /getactivescheme
            if ($currentPlan -match '([a-f0-9-]{36})') {
                $Matches[1] | Out-File "$backupFile`_powerplan.txt" -Encoding UTF8
            }
            # Save startup items
            reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" "$backupFile`_startup_hkcu.reg" /y 2>&1 | Out-Null
            $timestamp | Out-File "$backupPath\latest_backup.txt" -Encoding UTF8
            Write-Success "Backup created automatically"
        } catch {
            Write-Warn "Could not create automatic backup"
        }
        
        # ---------------------------------------------------------------------
        # PHASE 1: CLEANUP
        # ---------------------------------------------------------------------
        Write-Host ""
        Write-Host "  ===================== PHASE 1: CLEANUP =======================" -ForegroundColor Red
        Invoke-QuickClean
        
        # ---------------------------------------------------------------------
        # PREFETCH CLEANUP (Admin only)
        # ---------------------------------------------------------------------
        # Prefetch files help Windows launch programs faster by preloading
        # commonly used programs. But over time, old/unused entries accumulate.
        # Safe to delete: Windows rebuilds this automatically.
        #
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
        
        # ---------------------------------------------------------------------
        # PHASE 2: PERFORMANCE
        # ---------------------------------------------------------------------
        Write-Host ""
        Write-Host "  =================== PHASE 2: PERFORMANCE ====================" -ForegroundColor Red
        Invoke-PerformanceMode
        
        # ---------------------------------------------------------------------
        # PHASE 3: NETWORK
        # ---------------------------------------------------------------------
        Write-Host ""
        Write-Host "  ===================== PHASE 3: NETWORK ======================" -ForegroundColor Red
        Invoke-NetworkReset
        
        # ---------------------------------------------------------------------
        # PHASE 4: DEEP CLEANUP (Admin only)
        # ---------------------------------------------------------------------
        if ($isAdmin) {
            Write-Host ""
            Write-Host "  ================= PHASE 4: DEEP CLEANUP ====================" -ForegroundColor Red
            Invoke-DISMCleanup
        }
        
        # All done!
        Write-Host ""
        Write-Host "  ==============================================================" -ForegroundColor Green
        Write-Host "                   FULL TUNE-UP COMPLETE!                       " -ForegroundColor Green
        Write-Host "           Restart recommended for best results.                " -ForegroundColor Green
        Write-Host "  ==============================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "  [i] Your previous settings were backed up automatically." -ForegroundColor DarkGray
        Write-Host "      Use option [8] Restore Backup if needed." -ForegroundColor DarkGray
    }
    
    Pause-Script
}

# ===============================================================================
# PAUSE - WAIT FOR USER TO PRESS ENTER
# ===============================================================================
#
# WHAT THIS DOES:
# Simply waits for you to press Enter before continuing.
# Gives you time to read what just happened.
#

function Pause-Script {
    Write-Host ""
    Read-Host "  Press Enter to continue"
}

# ===============================================================================
# MAIN PROGRAM LOOP
# ===============================================================================
#
# WHAT THIS DOES:
# This is where the script actually starts running. It:
# 1. Shows the banner
# 2. Shows the menu
# 3. Waits for you to pick an option
# 4. Runs what you picked
# 5. Goes back to step 1 (until you choose Exit)
#
# The "do { } while ($choice -ne "0")" means: keep repeating this
# until the user picks option 0 (Exit).
#

do {
    # Show the cool banner with status info
    Show-Banner
    # Show the menu of options
    Show-Menu
    # Get user's choice
    $choice = Read-Host
    
    # Run the function that matches their choice
    switch ($choice) {
        "1" { Invoke-QuickClean }       # Clean temp files
        "2" { Invoke-StartupManager }    # Manage startup programs
        "3" { Invoke-PerformanceMode }   # Optimize for speed
        "4" { Invoke-NetworkReset }      # Fix network issues
        "5" { Invoke-DiskAnalysis }      # See what's using disk space
        "6" { Invoke-FullTuneUp }        # Run everything
        "7" { New-SettingsBackup }       # Create a backup
        "8" { Restore-SettingsBackup }   # Restore from backup
        "0" { 
            # Exit - say goodbye and end the loop
            Write-Host ""
            Write-Host "  Thanks for using PC Clean." -ForegroundColor Cyan
            Write-Host ""
            break 
        }
        default { 
            # They typed something we don't recognize
            Write-Host ""
            Write-Warn "Invalid option. Please try again."
            Start-Sleep -Seconds 1
        }
    }
} while ($choice -ne "0")

# ===============================================================================
# END OF SCRIPT
# ===============================================================================
#
# If you made it this far reading the code - thank you! 
# You now know exactly what this script does. No surprises, no hidden tricks.
#
# Questions or issues? Visit: https://github.com/bradley1320/pc-cleanup
#
# ===============================================================================
