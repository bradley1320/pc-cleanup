# ==============================================================================
# PC Cleanup v2 — UndoManager Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
    . "$PSScriptRoot/../../src/core/04-TweakEngine.ps1"
    . "$PSScriptRoot/../../src/core/05-UndoManager.ps1"
    . "$PSScriptRoot/../../src/handlers/RegistryHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ServiceHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/TaskHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ScriptHandler.ps1"
}

Describe 'Register-AppliedTweak' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        # Use a unique directory per test to prevent cross-contamination
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
    }

    It 'should create undo log directory if missing' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'TestTweak' -Changes $changes -Category 'Privacy'
        Test-Path $script:UndoLogDir | Should -BeTrue
    }

    It 'should append a new entry to the undo log' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'Tweak1' -Changes $changes -Category 'Privacy'
        Register-AppliedTweak -Name 'Tweak2' -Changes $changes -Category 'Performance'
        $log = Get-Content -Path $script:UndoLogPath -Raw | ConvertFrom-Json
        @($log).Count | Should -Be 2
    }

    It 'should include OS build number in the undo record' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'BuildTweak' -Changes $changes -Category 'Privacy'
        $log = Get-Content -Path $script:UndoLogPath -Raw | ConvertFrom-Json
        @($log)[0].AppliedOnBuild | Should -Be 22631
    }

    It 'should persist the undo log to disk' {
        $changes = @([PSCustomObject]@{ Type = 'Service'; Name = 'TestSvc'; OriginalStartupType = 'Automatic'; OriginalStatus = 'Running' })
        Register-AppliedTweak -Name 'PersistTweak' -Changes $changes -Category 'Privacy'
        Test-Path $script:UndoLogPath | Should -BeTrue
        $content = Get-Content -Path $script:UndoLogPath -Raw
        $content | Should -Not -BeNullOrEmpty
    }

    It 'should store original values captured at apply time' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 42; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'OriginalTweak' -Changes $changes -Category 'Privacy'
        $log = Get-Content -Path $script:UndoLogPath -Raw | ConvertFrom-Json
        $entry = @($log)[0]
        $entry.Changes[0].OriginalValue | Should -Be 42
        $entry.Changes[0].OriginalType | Should -Be 'DWord'
        $entry.Changes[0].KeyExistedBefore | Should -BeTrue
    }

    It 'should store category in the undo record' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'CatTweak' -Changes $changes -Category 'Performance'
        $log = Get-Content -Path $script:UndoLogPath -Raw | ConvertFrom-Json
        @($log)[0].Category | Should -Be 'Performance'
    }

    It 'should store ISO 8601 timestamp' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        $fixedTime = [datetime]'2025-06-15T10:30:00'
        Register-AppliedTweak -Name 'TimeTweak' -Changes $changes -Timestamp $fixedTime -Category 'Privacy'
        $log = Get-Content -Path $script:UndoLogPath -Raw | ConvertFrom-Json
        # PS Core's ConvertFrom-Json auto-converts ISO 8601 to DateTime; verify date components directly
        $parsed = [datetime]@($log)[0].AppliedAt
        $parsed.Year | Should -Be 2025
        $parsed.Month | Should -Be 6
        $parsed.Day | Should -Be 15
    }
}

Describe 'Get-AppliedTweaks' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
    }

    It 'should return empty array when no undo log exists' {
        $result = Get-AppliedTweaks
        $result | Should -HaveCount 0
    }

    It 'should return empty array when undo log is empty' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        '[]' | Set-Content -Path $script:UndoLogPath
        $result = Get-AppliedTweaks
        @($result).Count | Should -Be 0
    }

    It 'should return all applied tweaks with metadata' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'Tweak1' -Changes $changes -Category 'Privacy'
        Register-AppliedTweak -Name 'Tweak2' -Changes $changes -Category 'Performance'
        $result = Get-AppliedTweaks
        @($result).Count | Should -Be 2
        @($result)[0].TweakName | Should -Be 'Tweak1'
        @($result)[1].TweakName | Should -Be 'Tweak2'
    }

    It 'should handle corrupted undo log gracefully' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        'not valid json{{{' | Set-Content -Path $script:UndoLogPath
        $result = Get-AppliedTweaks
        $result | Should -HaveCount 0
    }
}

Describe 'Invoke-UndoTweak' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
    }

    It 'should warn when tweak is not found in undo log' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        '[]' | Set-Content -Path $script:UndoLogPath
        Invoke-UndoTweak -Name 'NonexistentTweak'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No undo data*' }
    }

    It 'should restore registry values from undo log' {
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        # Create a log entry with registry change
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'RegTweak' -Changes $changes -Category 'Privacy'
        Invoke-UndoTweak -Name 'RegTweak'
        Should -Invoke Set-PCCleanupRegistry -Times 1 -ParameterFilter { $Value -eq 1 -and $Type -eq 'DWord' }
    }

    It 'should remove registry entry when it did not exist before' {
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'NewVal'; OriginalValue = $null; OriginalType = $null; KeyExistedBefore = $false })
        Register-AppliedTweak -Name 'NewKeyTweak' -Changes $changes -Category 'Privacy'
        Invoke-UndoTweak -Name 'NewKeyTweak'
        Should -Invoke Set-PCCleanupRegistry -Times 1 -ParameterFilter { $Value -eq '<RemoveEntry>' }
    }

    It 'should restore service startup types from undo log' {
        Mock -CommandName Set-PCCleanupService -MockWith {}
        Mock -CommandName Start-Service -MockWith {}
        $changes = @([PSCustomObject]@{ Type = 'Service'; Name = 'TestSvc'; OriginalStartupType = 'Automatic'; OriginalStatus = 'Running' })
        Register-AppliedTweak -Name 'SvcTweak' -Changes $changes -Category 'Privacy'
        Invoke-UndoTweak -Name 'SvcTweak'
        Should -Invoke Set-PCCleanupService -Times 1 -ParameterFilter { $StartupType -eq 'Automatic' }
        Should -Invoke Start-Service -Times 1
    }

    It 'should warn if OS build changed since tweak was applied' {
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'BuildChangeTweak' -Changes $changes -Category 'Privacy'
        # Change the mock to return a different build
        Mock -CommandName Get-OSBuild -MockWith { 26100 }
        Invoke-UndoTweak -Name 'BuildChangeTweak'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*build*' -and $ForegroundColor -eq 'Yellow' }
    }

    It 'should remove the tweak entry from undo log after successful undo' {
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'RemoveTweak' -Changes $changes -Category 'Privacy'
        Register-AppliedTweak -Name 'KeepTweak' -Changes $changes -Category 'Performance'
        Invoke-UndoTweak -Name 'RemoveTweak'
        $remaining = Get-AppliedTweaks
        @($remaining).Count | Should -Be 1
        @($remaining)[0].TweakName | Should -Be 'KeepTweak'
    }
}

Describe 'Invoke-UndoAll' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
    }

    It 'should report when no tweaks are applied' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        '[]' | Set-Content -Path $script:UndoLogPath
        Invoke-UndoAll
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No applied tweaks*' }
    }

    It 'should undo all tweaks in reverse chronological order' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'First' -Changes $changes -Timestamp ([datetime]'2025-01-01T10:00:00') -Category 'Privacy'
        Register-AppliedTweak -Name 'Second' -Changes $changes -Timestamp ([datetime]'2025-01-02T10:00:00') -Category 'Privacy'
        Invoke-UndoAll
        $remaining = Get-AppliedTweaks
        @($remaining).Count | Should -Be 0
    }
}
