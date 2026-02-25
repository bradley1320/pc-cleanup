# ==============================================================================
# PC Cleanup v2 — TweakEngine Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
    . "$PSScriptRoot/../../src/core/05-UndoManager.ps1"
    . "$PSScriptRoot/../../src/core/04-TweakEngine.ps1"
    . "$PSScriptRoot/../../src/handlers/RegistryHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ServiceHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/TaskHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ScriptHandler.ps1"
}

Describe 'Get-Tweaks' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        $script:SchemaValidated = $false

        # Set up test tweaks.json in TestDrive
        $script:ConfigPath = $TestDrive
        $testTweaks = @{
            '_version' = '2.0.0'
            'SafePrivacy' = @{
                name = 'Safe Privacy Tweak'
                description = 'A safe privacy tweak'
                detail = 'Detail text'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'ModeratePrivacy' = @{
                name = 'Moderate Privacy Tweak'
                description = 'A moderate privacy tweak'
                detail = 'Detail text'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'moderate'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $true
                registry = @(@{ path = 'HKLM:\Test'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @(@{ name = 'TestSvc'; startupType = 'Disabled'; defaultType = 'Automatic' })
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'AdvancedPrivacy' = @{
                name = 'Advanced Privacy Tweak'
                description = 'An advanced privacy tweak'
                detail = 'Detail text'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'advanced'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $true
                registry = @(@{ path = 'HKLM:\Test'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'SafePerformance' = @{
                name = 'Safe Perf Tweak'
                description = 'A safe performance tweak'
                detail = 'Detail text'
                docsUrl = 'https://example.com'
                category = 'Performance'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test'; name = 'PerfVal'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'NewBuildOnly' = @{
                name = 'New Build Tweak'
                description = 'Only for new builds'
                detail = 'Detail text'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = 99999
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test'; name = 'NewVal'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'OldBuildOnly' = @{
                name = 'Old Build Tweak'
                description = 'Only for old builds'
                detail = 'Detail text'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = 10000
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test'; name = 'OldVal'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
    }

    It 'should load and parse tweaks.json' {
        $result = Get-Tweaks -RiskLevel 'advanced'
        $result | Should -Not -BeNullOrEmpty
    }

    It 'should exclude metadata keys starting with underscore' {
        $result = Get-Tweaks -RiskLevel 'advanced'
        $result | Where-Object { $_.Id -eq '_version' } | Should -BeNullOrEmpty
    }

    It 'should add Id property from JSON key name' {
        $result = Get-Tweaks -RiskLevel 'advanced'
        ($result | Where-Object { $_.Id -eq 'SafePrivacy' }) | Should -Not -BeNullOrEmpty
    }

    It 'should filter by category' {
        $result = Get-Tweaks -Category 'Performance' -RiskLevel 'advanced'
        @($result).Count | Should -Be 1
        $result[0].Id | Should -Be 'SafePerformance'
    }

    It 'should return only safe tweaks at safe risk level' {
        $result = Get-Tweaks -Category 'Privacy' -RiskLevel 'safe'
        $result | ForEach-Object { $_.risk | Should -Be 'safe' }
    }

    It 'should return safe and moderate tweaks at moderate risk level' {
        $result = Get-Tweaks -Category 'Privacy' -RiskLevel 'moderate'
        $result | ForEach-Object { $_.risk | Should -BeIn @('safe', 'moderate') }
        ($result | Where-Object { $_.risk -eq 'moderate' }) | Should -Not -BeNullOrEmpty
    }

    It 'should return all tweaks at advanced risk level' {
        $result = Get-Tweaks -Category 'Privacy' -RiskLevel 'advanced'
        ($result | Where-Object { $_.risk -eq 'advanced' }) | Should -Not -BeNullOrEmpty
    }

    It 'should skip tweaks above minBuild' {
        $result = Get-Tweaks -RiskLevel 'safe'
        ($result | Where-Object { $_.Id -eq 'NewBuildOnly' }) | Should -BeNullOrEmpty
    }

    It 'should skip tweaks below maxBuild' {
        $result = Get-Tweaks -RiskLevel 'safe'
        ($result | Where-Object { $_.Id -eq 'OldBuildOnly' }) | Should -BeNullOrEmpty
    }

    It 'should throw on missing tweaks.json' {
        $script:ConfigPath = Join-Path $TestDrive 'nonexistent'
        $script:SchemaValidated = $false
        { Get-Tweaks } | Should -Throw '*not found*'
    }

    It 'should validate JSON schema on first load' {
        # Remove a required field to trigger validation failure
        $badTweaks = @{
            'BadTweak' = @{
                name = 'Bad Tweak'
                description = 'Missing fields'
            }
        }
        $badTweaks | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        $script:SchemaValidated = $false
        { Get-Tweaks } | Should -Throw '*invalid*'
    }

    It 'should include tweaks matching current OS build' {
        # Create a tweak that matches current mock build 22631
        $matchTweaks = @{
            'MatchBuild' = @{
                name = 'Match Build Tweak'
                description = 'Matches current build'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = 22000
                maxBuild = 23000
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $matchTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        $script:SchemaValidated = $false
        $result = Get-Tweaks -RiskLevel 'safe'
        ($result | Where-Object { $_.Id -eq 'MatchBuild' }) | Should -Not -BeNullOrEmpty
    }
}

Describe 'Invoke-Tweak' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        Mock -CommandName Get-PCCleanupRegistryValue -MockWith {
            [PSCustomObject]@{ Value = 1; Type = 'DWord'; Exists = $true }
        }
        Mock -CommandName Set-PCCleanupService -MockWith {}
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'TestSvc'; StartType = 'Automatic'; Status = 'Running' }
        }
        Mock -CommandName Set-PCCleanupScheduledTask -MockWith {}
        Mock -CommandName Get-ScheduledTask -MockWith {
            [PSCustomObject]@{ TaskName = 'TestTask'; State = 'Ready' }
        }
        Mock -CommandName Invoke-PCCleanupScript -MockWith {}

        $script:SchemaValidated = $true
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'

        # Set up test config
        $script:ConfigPath = $TestDrive
        $testTweaks = @{
            'TestRegTweak' = @{
                name = 'Test Registry Tweak'
                description = 'Test tweak with registry'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'TestSvcTweak' = @{
                name = 'Test Service Tweak'
                description = 'Test tweak with service'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'moderate'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $true
                registry = @()
                services = @(@{ name = 'TestSvc'; startupType = 'Disabled'; defaultType = 'Automatic' })
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'TestTaskTweak' = @{
                name = 'Test Task Tweak'
                description = 'Test tweak with task'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $true
                registry = @()
                services = @()
                scheduledTasks = @(@{ path = '\Microsoft\Windows\Test\TestTask'; enabled = $false })
                invokeScript = @()
                undoScript = @()
            }
            'TestScriptTweak' = @{
                name = 'Test Script Tweak'
                description = 'Test tweak with script'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @()
                services = @()
                scheduledTasks = @()
                invokeScript = @('Write-Host "test"')
                undoScript = @()
            }
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
    }

    It 'should dispatch registry entries to Set-PCCleanupRegistry' {
        Invoke-Tweak -Name 'TestRegTweak'
        Should -Invoke Set-PCCleanupRegistry -Times 1
    }

    It 'should dispatch services to Set-PCCleanupService' {
        Invoke-Tweak -Name 'TestSvcTweak'
        Should -Invoke Set-PCCleanupService -Times 1
    }

    It 'should dispatch scheduled tasks to Set-PCCleanupScheduledTask' {
        Invoke-Tweak -Name 'TestTaskTweak'
        Should -Invoke Set-PCCleanupScheduledTask -Times 1
    }

    It 'should dispatch invokeScript to Invoke-PCCleanupScript' {
        Invoke-Tweak -Name 'TestScriptTweak'
        Should -Invoke Invoke-PCCleanupScript -Times 1
    }

    It 'should register applied tweak with UndoManager on apply' {
        Invoke-Tweak -Name 'TestRegTweak'
        $log = Get-AppliedTweaks
        @($log).Count | Should -BeGreaterThan 0
        (@($log) | Where-Object { $_.TweakName -eq 'TestRegTweak' }) | Should -Not -BeNullOrEmpty
    }

    It 'should capture original registry value before applying' {
        Invoke-Tweak -Name 'TestRegTweak'
        Should -Invoke Get-PCCleanupRegistryValue -Times 1
    }

    It 'should call Invoke-UndoTweak when Undo switch is set' {
        Mock -CommandName Invoke-UndoTweak -MockWith {}
        Invoke-Tweak -Name 'TestRegTweak' -Undo
        Should -Invoke Invoke-UndoTweak -Times 1 -ParameterFilter { $Name -eq 'TestRegTweak' }
    }

    It 'should warn when tweak not found in tweaks.json' {
        Invoke-Tweak -Name 'NonexistentTweak'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*not found*' }
    }

    It 'should register script undo data for tweaks with undoScript only' {
        # Add a script-only tweak with undoScript
        $testTweaks = @{
            'ScriptOnlyTweak' = @{
                name = 'Script Only Tweak'
                description = 'Tweak with only invokeScript and undoScript'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @()
                services = @()
                scheduledTasks = @()
                invokeScript = @('Write-Host "apply"')
                undoScript = @('Write-Host "undo"')
            }
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        Invoke-Tweak -Name 'ScriptOnlyTweak'
        $log = Get-AppliedTweaks
        @($log).Count | Should -BeGreaterThan 0
        $entry = @($log | Where-Object { $_.TweakName -eq 'ScriptOnlyTweak' })
        $entry.Count | Should -Be 1
        $entry[0].Changes[0].Type | Should -Be 'Script'
    }

    It 'should not register undo when undoScript is empty' {
        Invoke-Tweak -Name 'TestScriptTweak'
        $log = Get-AppliedTweaks
        @($log | Where-Object { $_.TweakName -eq 'TestScriptTweak' }).Count | Should -Be 0
    }

    It 'should NOT store UndoCommands in undo_log.json (security: prevents injection)' {
        $testTweaks = @{
            'ScriptSecurityTweak' = @{
                name = 'Script Security Tweak'
                description = 'Tweak to test undo command storage'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @()
                services = @()
                scheduledTasks = @()
                invokeScript = @('Write-Host "apply"')
                undoScript = @('Write-Host "undo"')
            }
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        Invoke-Tweak -Name 'ScriptSecurityTweak'
        $log = Get-AppliedTweaks
        $entry = @($log | Where-Object { $_.TweakName -eq 'ScriptSecurityTweak' })
        # Verify no UndoCommands field in the stored change
        $entry[0].Changes[0].PSObject.Properties.Name | Should -Not -Contain 'UndoCommands'
    }

    It 'should execute undoScript from tweaks.json at undo time (not from undo log)' {
        # Set up tweaks.json with the undoScript
        $testTweaks = @{
            'ScriptUndoTest' = @{
                name = 'Script Undo Test'
                description = 'Test script undo lookup'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @()
                services = @()
                scheduledTasks = @()
                invokeScript = @('Write-Host "apply"')
                undoScript = @('Write-Host "undone from tweaks.json"')
            }
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        # Register a Script undo marker (no UndoCommands stored)
        $scriptChanges = @([PSCustomObject]@{ Type = 'Script' })
        Register-AppliedTweak -Name 'ScriptUndoTest' -Changes $scriptChanges -Category 'Privacy'
        Invoke-UndoTweak -Name 'ScriptUndoTest'
        Should -Invoke Invoke-PCCleanupScript -Times 1 -ParameterFilter { $ScriptBlock -eq 'Write-Host "undone from tweaks.json"' }
    }

    It 'should register Script marker for hybrid tweaks (registry + undoScript)' {
        $testTweaks = @{
            'HybridTweak' = @{
                name = 'Hybrid Tweak'
                description = 'Tweak with both registry and undoScript'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @('Write-Host "apply script part"')
                undoScript = @('Write-Host "undo script part"')
            }
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        Invoke-Tweak -Name 'HybridTweak'
        $log = Get-AppliedTweaks
        $entry = @($log | Where-Object { $_.TweakName -eq 'HybridTweak' })
        $entry.Count | Should -Be 1
        # Should have both Registry and Script changes
        $changeTypes = @($entry[0].Changes | ForEach-Object { $_.Type })
        $changeTypes | Should -Contain 'Registry'
        $changeTypes | Should -Contain 'Script'
    }

    It 'should warn when tweaks.json missing during script undo' {
        $scriptChanges = @([PSCustomObject]@{ Type = 'Script' })
        Register-AppliedTweak -Name 'MissingJsonTweak' -Changes $scriptChanges -Category 'Privacy'
        # Point config to a nonexistent path
        $script:ConfigPath = Join-Path $TestDrive 'nonexistent_config'
        Invoke-UndoTweak -Name 'MissingJsonTweak'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Cannot execute script undo*' }
    }
}

Describe 'Invoke-TweakSet' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        Mock -CommandName Invoke-Tweak -MockWith {}
        $script:SchemaValidated = $true

        $script:ConfigPath = $TestDrive
        $testTweaks = @{
            'Safe1' = @{
                name = 'Safe Tweak 1'
                description = 'First safe tweak'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val1'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'Safe2' = @{
                name = 'Safe Tweak 2'
                description = 'Second safe tweak'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val2'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'Moderate1' = @{
                name = 'Moderate Tweak 1'
                description = 'A moderate tweak'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'moderate'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $true
                registry = @(@{ path = 'HKLM:\Test'; name = 'Val3'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
    }

    It 'should apply all tweaks matching category and risk level' {
        Invoke-TweakSet -Category 'Privacy' -RiskLevel 'safe'
        Should -Invoke Invoke-Tweak -Times 2
    }

    It 'should skip tweaks above the specified risk level' {
        Invoke-TweakSet -Category 'Privacy' -RiskLevel 'safe'
        Should -Invoke Invoke-Tweak -Times 2
        # Moderate1 should not be invoked at safe level
        Should -Invoke Invoke-Tweak -Times 0 -ParameterFilter { $Name -eq 'Moderate1' }
    }

    It 'should include lower risk tweaks at higher risk level' {
        Invoke-TweakSet -Category 'Privacy' -RiskLevel 'moderate'
        Should -Invoke Invoke-Tweak -Times 3
    }

    It 'should report when no tweaks match' {
        Invoke-TweakSet -Category 'Nonexistent' -RiskLevel 'safe'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No tweaks found*' }
    }

    It 'should pass Undo switch through to Invoke-Tweak' {
        Invoke-TweakSet -Category 'Privacy' -RiskLevel 'safe' -Undo
        Should -Invoke Invoke-Tweak -ParameterFilter { $Undo -eq $true }
    }
}
