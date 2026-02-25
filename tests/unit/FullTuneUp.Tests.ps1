BeforeAll {
    # Load dependencies in order
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
    . "$PSScriptRoot/../../src/core/03-SafetyNet.ps1"
    . "$PSScriptRoot/../../src/core/04-TweakEngine.ps1"
    . "$PSScriptRoot/../../src/core/05-UndoManager.ps1"
    . "$PSScriptRoot/../../src/core/06-SafeFileOps.ps1"
    . "$PSScriptRoot/../../src/handlers/RegistryHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ServiceHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/TaskHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ScriptHandler.ps1"
    . "$PSScriptRoot/../../src/modules/QuickClean.ps1"
    . "$PSScriptRoot/../../src/modules/PerformanceMode.ps1"
    . "$PSScriptRoot/../../src/modules/PrivacyShield.ps1"
    . "$PSScriptRoot/../../src/modules/SystemReport.ps1"
    . "$PSScriptRoot/../../src/modules/FullTuneUp.ps1"
}

Describe 'Invoke-FullTuneUp' {
    BeforeEach {
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
        $script:SnapshotDir = Join-Path $TestDrive 'snapshots'
        $script:SchemaValidated = $false
    }

    It 'should return a summary object' {
        Mock New-SafetyRestorePoint { return $false }
        Mock Backup-RegistryHive { return $null }
        Mock Save-SystemSnapshot { return [PSCustomObject]@{ BootTimeMs = 1000 } }
        Mock Get-CleanupTargets { return @() }
        Mock Get-Tweaks { return @() }
        Mock Invoke-Tweak {}
        Mock Test-IsAdmin { return $false }

        $result = Invoke-FullTuneUp
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'RestorePoint'
        $result.PSObject.Properties.Name | Should -Contain 'CleanupFiles'
        $result.PSObject.Properties.Name | Should -Contain 'PerformanceTweaks'
        $result.PSObject.Properties.Name | Should -Contain 'PrivacyTweaks'
    }

    It 'should call safety functions first' {
        Mock New-SafetyRestorePoint { return $true }
        Mock Backup-RegistryHive { return 'C:\backup.reg' }
        Mock Save-SystemSnapshot { return [PSCustomObject]@{ BootTimeMs = 1000 } }
        Mock Get-CleanupTargets { return @() }
        Mock Get-Tweaks { return @() }
        Mock Invoke-Tweak {}
        Mock Test-IsAdmin { return $false }

        $result = Invoke-FullTuneUp
        $result.RestorePoint | Should -Be $true
        $result.RegistryBackup | Should -Be $true
        Should -Invoke New-SafetyRestorePoint -Times 1
        Should -Invoke Backup-RegistryHive -Times 1
    }

    It 'should run QuickClean with all targets' {
        Mock New-SafetyRestorePoint { return $false }
        Mock Backup-RegistryHive { return $null }
        Mock Save-SystemSnapshot { return [PSCustomObject]@{ BootTimeMs = 1000 } }
        $script:mockTargets = @([PSCustomObject]@{ Name = 'Test'; Path = 'C:\temp'; FileCount = 5; Size = 1024; Type = 'temp'; RequiresAdmin = $false })
        Mock Get-CleanupTargets { return $script:mockTargets }
        Mock Invoke-Cleanup { return [PSCustomObject]@{ TotalFiles = 5; TotalBytes = [long]1024; SkippedFiles = 0; Errors = 0 } }
        Mock Get-Tweaks { return @() }
        Mock Invoke-Tweak {}
        Mock Test-IsAdmin { return $false }

        $result = Invoke-FullTuneUp
        $result.CleanupFiles | Should -Be 5
        $result.CleanupBytes | Should -Be 1024
        Should -Invoke Invoke-Cleanup -Times 1
    }

    It 'should apply performance and privacy tweaks' {
        Mock New-SafetyRestorePoint { return $false }
        Mock Backup-RegistryHive { return $null }
        Mock Save-SystemSnapshot { return [PSCustomObject]@{ BootTimeMs = 1000 } }
        Mock Get-CleanupTargets { return @() }
        Mock Get-Tweaks {
            if ($Category -eq 'Performance') {
                return @([PSCustomObject]@{ Id = 'TestPerf'; name = 'Test Perf'; risk = 'safe' })
            }
            if ($Category -eq 'Privacy') {
                return @([PSCustomObject]@{ Id = 'TestPrivacy'; name = 'Test Privacy'; risk = 'safe' })
            }
            return @()
        }
        Mock Invoke-Tweak {}
        Mock Test-IsAdmin { return $false }

        $result = Invoke-FullTuneUp
        $result.PerformanceTweaks | Should -Be 1
        $result.PrivacyTweaks | Should -Be 1
        Should -Invoke Invoke-Tweak -Times 2
    }

    It 'should not run DISM or Prefetch without admin' {
        Mock New-SafetyRestorePoint { return $false }
        Mock Backup-RegistryHive { return $null }
        Mock Save-SystemSnapshot { return [PSCustomObject]@{ BootTimeMs = 1000 } }
        Mock Get-CleanupTargets { return @() }
        Mock Get-Tweaks { return @() }
        Mock Invoke-Tweak {}
        Mock Test-IsAdmin { return $false }

        $result = Invoke-FullTuneUp
        $result.PrefetchCleaned | Should -Be $false
        $result.DismRun | Should -Be $false
    }

    It 'should work in WhatIf mode without modifying anything' {
        Mock New-SafetyRestorePoint { throw 'Should not be called in WhatIf' }
        Mock Backup-RegistryHive { throw 'Should not be called in WhatIf' }
        Mock Save-SystemSnapshot { throw 'Should not be called in WhatIf' }
        Mock Get-CleanupTargets { return @() }
        Mock Get-Tweaks { return @() }
        Mock Invoke-Tweak { throw 'Should not be called in WhatIf' }
        Mock Invoke-Cleanup { throw 'Should not be called in WhatIf' }
        Mock Test-IsAdmin { return $false }

        $result = Invoke-FullTuneUp -WhatIf
        $result | Should -Not -BeNullOrEmpty
        $result.RestorePoint | Should -Be $false
    }

    It 'should count performance and privacy tweaks in WhatIf mode' {
        Mock Get-CleanupTargets { return @() }
        Mock Get-Tweaks {
            if ($Category -eq 'Performance') {
                return @([PSCustomObject]@{ Id = 'TestPerf'; name = 'Test Perf'; risk = 'safe' })
            }
            if ($Category -eq 'Privacy') {
                return @([PSCustomObject]@{ Id = 'TestPrivacy'; name = 'Test Privacy'; risk = 'safe' })
            }
            return @()
        }
        Mock Test-IsAdmin { return $false }

        $result = Invoke-FullTuneUp -WhatIf
        $result.PerformanceTweaks | Should -Be 1
        $result.PrivacyTweaks | Should -Be 1
    }
}
