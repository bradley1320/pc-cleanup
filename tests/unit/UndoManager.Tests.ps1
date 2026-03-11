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

    It 'should skip entries with missing TweakName' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        @([PSCustomObject]@{
            AppliedAt = (Get-Date).ToString('o')
            AppliedOnBuild = 22631
            Category = 'Privacy'
            Changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        }) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:UndoLogPath
        $result = Get-AppliedTweaks
        $result | Should -HaveCount 0
    }

    It 'should skip entries with empty Changes array' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        @([PSCustomObject]@{
            TweakName = 'BadTweak'
            AppliedAt = (Get-Date).ToString('o')
            AppliedOnBuild = 22631
            Category = 'Privacy'
            Changes = @()
        }) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:UndoLogPath
        $result = Get-AppliedTweaks
        $result | Should -HaveCount 0
    }

    It 'should skip entries with invalid change Type' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        @([PSCustomObject]@{
            TweakName = 'InjectionTweak'
            AppliedAt = (Get-Date).ToString('o')
            AppliedOnBuild = 22631
            Category = 'Privacy'
            Changes = @([PSCustomObject]@{ Type = 'Exec'; Command = 'malicious-command' })
        }) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:UndoLogPath
        $result = Get-AppliedTweaks
        $result | Should -HaveCount 0
    }

    It 'should skip registry changes with missing Path' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        @([PSCustomObject]@{
            TweakName = 'BadReg'
            AppliedAt = (Get-Date).ToString('o')
            AppliedOnBuild = 22631
            Category = 'Privacy'
            Changes = @([PSCustomObject]@{ Type = 'Registry'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        }) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:UndoLogPath
        $result = Get-AppliedTweaks
        $result | Should -HaveCount 0
    }

    It 'should keep valid entries and skip invalid ones in mixed log' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'ValidTweak' -Changes $changes -Category 'Privacy'
        # Inject a malformed entry directly into the log
        $log = Get-Content -Path $script:UndoLogPath -Raw | ConvertFrom-Json
        $log = @($log)
        $log += [PSCustomObject]@{ TweakName = ''; AppliedAt = ''; Changes = $null }
        $log | ConvertTo-Json -Depth 10 | Set-Content -Path $script:UndoLogPath
        $result = Get-AppliedTweaks
        @($result).Count | Should -Be 1
        @($result)[0].TweakName | Should -Be 'ValidTweak'
    }
}

Describe 'Test-UndoLogEntry' {
    It 'should accept valid registry entry' {
        $entry = [PSCustomObject]@{
            TweakName = 'TestTweak'
            AppliedAt = (Get-Date).ToString('o')
            Changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        }
        Test-UndoLogEntry $entry | Should -BeTrue
    }

    It 'should accept valid service entry' {
        $entry = [PSCustomObject]@{
            TweakName = 'SvcTweak'
            AppliedAt = (Get-Date).ToString('o')
            Changes = @([PSCustomObject]@{ Type = 'Service'; Name = 'TestSvc'; OriginalStartupType = 'Automatic'; OriginalStatus = 'Running' })
        }
        Test-UndoLogEntry $entry | Should -BeTrue
    }

    It 'should accept valid scheduled task entry' {
        $entry = [PSCustomObject]@{
            TweakName = 'TaskTweak'
            AppliedAt = (Get-Date).ToString('o')
            Changes = @([PSCustomObject]@{ Type = 'ScheduledTask'; Path = '\Microsoft\Windows\Test'; OriginalEnabled = $true })
        }
        Test-UndoLogEntry $entry | Should -BeTrue
    }

    It 'should accept valid script entry' {
        $entry = [PSCustomObject]@{
            TweakName = 'ScriptTweak'
            AppliedAt = (Get-Date).ToString('o')
            Changes = @([PSCustomObject]@{ Type = 'Script' })
        }
        Test-UndoLogEntry $entry | Should -BeTrue
    }

    It 'should reject null entry' {
        Test-UndoLogEntry $null | Should -BeFalse
    }

    It 'should reject entry with null TweakName' {
        $entry = [PSCustomObject]@{ TweakName = $null; AppliedAt = 'x'; Changes = @(@{Type='Script'}) }
        Test-UndoLogEntry $entry | Should -BeFalse
    }

    It 'should reject entry with unknown change Type' {
        $entry = [PSCustomObject]@{
            TweakName = 'Bad'
            AppliedAt = (Get-Date).ToString('o')
            Changes = @([PSCustomObject]@{ Type = 'Exec'; Command = 'rm -rf /' })
        }
        Test-UndoLogEntry $entry | Should -BeFalse
    }

    It 'should reject registry change without Path' {
        $entry = [PSCustomObject]@{
            TweakName = 'Bad'
            AppliedAt = (Get-Date).ToString('o')
            Changes = @([PSCustomObject]@{ Type = 'Registry'; Name = 'Val' })
        }
        Test-UndoLogEntry $entry | Should -BeFalse
    }

    It 'should reject service change without Name' {
        $entry = [PSCustomObject]@{
            TweakName = 'Bad'
            AppliedAt = (Get-Date).ToString('o')
            Changes = @([PSCustomObject]@{ Type = 'Service'; OriginalStartupType = 'Automatic' })
        }
        Test-UndoLogEntry $entry | Should -BeFalse
    }

    It 'should accept valid StartupRegistry entry' {
        $entry = [PSCustomObject]@{
            TweakName = 'Startup_TestApp'
            AppliedAt = (Get-Date).ToString('o')
            Changes = @([PSCustomObject]@{ Type = 'StartupRegistry'; Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name = 'TestApp'; Command = 'C:\test.exe' })
        }
        Test-UndoLogEntry $entry | Should -BeTrue
    }

    It 'should accept valid StartupFolder entry with FilePath' {
        $entry = [PSCustomObject]@{
            TweakName = 'Startup_TestLink'
            AppliedAt = (Get-Date).ToString('o')
            Changes = @([PSCustomObject]@{ Type = 'StartupFolder'; FilePath = 'C:\Users\test\Startup\test.lnk'; FileName = 'test.lnk' })
        }
        Test-UndoLogEntry $entry | Should -BeTrue
    }

    It 'should reject StartupFolder entry without FilePath' {
        $entry = [PSCustomObject]@{
            TweakName = 'Startup_Bad'
            AppliedAt = (Get-Date).ToString('o')
            Changes = @([PSCustomObject]@{ Type = 'StartupFolder'; FileName = 'test.lnk' })
        }
        Test-UndoLogEntry $entry | Should -BeFalse
    }

    It 'should reject StartupRegistry entry without Path' {
        $entry = [PSCustomObject]@{
            TweakName = 'Startup_Bad'
            AppliedAt = (Get-Date).ToString('o')
            Changes = @([PSCustomObject]@{ Type = 'StartupRegistry'; Name = 'TestApp'; Command = 'test.exe' })
        }
        Test-UndoLogEntry $entry | Should -BeFalse
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

    It 'should refuse to undo a malformed entry injected directly into log' {
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        # Write a malformed entry directly (bypassing Register-AppliedTweak validation)
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        @([PSCustomObject]@{
            TweakName = 'InjectedTweak'
            AppliedAt = (Get-Date).ToString('o')
            AppliedOnBuild = 22631
            Category = 'Privacy'
            Changes = @([PSCustomObject]@{ Type = 'Exec'; Command = 'malicious-command' })
        }) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:UndoLogPath
        Invoke-UndoTweak -Name 'InjectedTweak'
        # Should NOT have called any handler
        Should -Invoke Set-PCCleanupRegistry -Times 0
    }

    It 'should restore StartupRegistry entries' {
        Mock -CommandName Set-ItemProperty -MockWith {}
        Mock -CommandName New-Item -MockWith {} -ParameterFilter { $ItemType -ne 'Directory' }
        Mock -CommandName Test-Path -MockWith { return $true } -ParameterFilter { $Path -and $Path -like 'HKCU:*' }
        $changes = @([PSCustomObject]@{ Type = 'StartupRegistry'; Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name = 'TestApp'; Command = 'C:\test.exe' })
        Register-AppliedTweak -Name 'Startup_TestApp' -Changes $changes -Category 'Startup'
        Invoke-UndoTweak -Name 'Startup_TestApp'
        Should -Invoke Set-ItemProperty -Times 1
    }

    It 'should restore StartupFolder entries by renaming disabled file' {
        # Use a valid startup folder path (allowlisted by the security check)
        $startupFolder = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
        $testFilePath = Join-Path $startupFolder 'test.lnk'
        $disabledPath = "$testFilePath.disabled"
        Mock -CommandName Rename-Item -MockWith {}
        Mock -CommandName Test-Path -MockWith { return $true } -ParameterFilter { $LiteralPath -and $LiteralPath -eq $disabledPath }
        $changes = @([PSCustomObject]@{ Type = 'StartupFolder'; FilePath = $testFilePath; FileName = 'test.lnk' })
        Register-AppliedTweak -Name 'Startup_TestLink' -Changes $changes -Category 'Startup'
        Invoke-UndoTweak -Name 'Startup_TestLink'
        Should -Invoke Rename-Item -Times 1
    }

    It 'should block undo with registry path not in tweak definition' {
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        # Set up tweaks.json with a tweak that only allows HKCU:\Test\Val
        $script:ConfigPath = $TestDrive
        $testTweaks = @{
            'LegitTweak' = @{
                name = 'Legit Tweak'
                description = 'Test'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        # Register an undo entry with an INJECTED registry path (not in the tweak def)
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name = 'Backdoor'; OriginalValue = 'C:\evil.exe'; OriginalType = 'String'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'LegitTweak' -Changes $changes -Category 'Privacy'
        Invoke-UndoTweak -Name 'LegitTweak'
        # The injected path should be BLOCKED -- Set-PCCleanupRegistry should NOT be called
        Should -Invoke Set-PCCleanupRegistry -Times 0
    }

    It 'should allow undo with registry path matching tweak definition' {
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        $script:ConfigPath = $TestDrive
        $testTweaks = @{
            'ValidTweak' = @{
                name = 'Valid Tweak'
                description = 'Test'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKCU:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'ValidTweak' -Changes $changes -Category 'Privacy'
        Invoke-UndoTweak -Name 'ValidTweak'
        Should -Invoke Set-PCCleanupRegistry -Times 1
    }

    It 'should bypass path validation for StartupRegistry changes' {
        Mock -CommandName Set-ItemProperty -MockWith {}
        Mock -CommandName New-Item -MockWith {} -ParameterFilter { $ItemType -ne 'Directory' }
        Mock -CommandName Test-Path -MockWith { return $true } -ParameterFilter { $Path -and $Path -like 'HKCU:*' }
        $script:ConfigPath = $TestDrive
        # Even with no tweaks.json tweak def, StartupRegistry should still work
        $testTweaks = @{}
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        $changes = @([PSCustomObject]@{ Type = 'StartupRegistry'; Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Name = 'TestApp'; Command = 'C:\test.exe' })
        Register-AppliedTweak -Name 'Startup_TestApp' -Changes $changes -Category 'Startup'
        Invoke-UndoTweak -Name 'Startup_TestApp'
        Should -Invoke Set-ItemProperty -Times 1
    }

    It 'should gracefully skip path validation when tweaks.json is missing' {
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        $script:ConfigPath = Join-Path $TestDrive 'nonexistent_config'
        # Without tweaks.json, path validation is skipped (graceful degradation)
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKCU:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'NoJsonTweak' -Changes $changes -Category 'Privacy'
        Invoke-UndoTweak -Name 'NoJsonTweak'
        # Should still proceed with undo since we can't validate
        Should -Invoke Set-PCCleanupRegistry -Times 1
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
