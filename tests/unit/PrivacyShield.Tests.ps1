# ==============================================================================
# PC Cleanup v2 -- PrivacyShield Tests (Pester 5.x)
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
    . "$PSScriptRoot/../../src/modules/PrivacyShield.ps1"
}

Describe 'Show-PrivacyMenu' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        Mock -CommandName Read-Host -MockWith { 'B' }
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

        # Test tweaks.json with privacy tweaks at different risk tiers
        $script:ConfigPath = $TestDrive
        $testTweaks = @{
            '_version' = '2.0.0'
            'SafePrivacy1' = @{
                name = 'Safe Privacy 1'
                description = 'First safe privacy tweak'
                detail = 'Detail about safe privacy 1'
                docsUrl = 'https://example.com/safe1'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test\Safe1'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'SafePrivacy2' = @{
                name = 'Safe Privacy 2'
                description = 'Second safe privacy tweak'
                detail = 'Detail about safe privacy 2'
                docsUrl = 'https://example.com/safe2'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test\Safe2'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'ModeratePrivacy1' = @{
                name = 'Moderate Privacy 1'
                description = 'A moderate privacy tweak'
                detail = 'Detail about moderate privacy'
                docsUrl = 'https://example.com/moderate1'
                category = 'Privacy'
                risk = 'moderate'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $true
                registry = @(@{ path = 'HKLM:\Test\Mod1'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'AdvancedPrivacy1' = @{
                name = 'Advanced Privacy 1'
                description = 'An advanced privacy tweak'
                detail = 'Detail about advanced privacy'
                docsUrl = 'https://example.com/advanced1'
                category = 'Privacy'
                risk = 'advanced'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $true
                registry = @(@{ path = 'HKLM:\Test\Adv1'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
    }

    It 'should load only Privacy category tweaks' {
        Show-PrivacyMenu -RiskLevel 'safe'
        # Should display safe tweaks and the menu prompt
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Safe Privacy*' }
    }

    It 'should respect risk level parameter' {
        Show-PrivacyMenu -RiskLevel 'safe'
        # Should NOT show moderate tweaks at safe level
        Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -like '*Moderate Privacy*' }
    }

    It 'should show moderate tweaks when risk level is moderate' {
        Show-PrivacyMenu -RiskLevel 'moderate'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Moderate Privacy*' }
    }

    It 'should display tier headers' {
        Show-PrivacyMenu -RiskLevel 'advanced'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*SAFE TIER*' }
    }

    It 'should show applied status from undo log' {
        # Apply a tweak first
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKCU:\Test\Safe1'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'SafePrivacy1' -Changes $changes -Category 'Privacy'
        Show-PrivacyMenu -RiskLevel 'safe'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*`[X`]*Safe Privacy 1*' }
    }

    It 'should apply all unapplied tweaks on A command' {
        Mock -CommandName Read-Host -MockWith { 'A' }
        Show-PrivacyMenu -RiskLevel 'safe'
        Should -Invoke Set-PCCleanupRegistry -Times 2
    }

    It 'should undo all applied tweaks on U command' {
        Mock -CommandName Read-Host -MockWith { 'U' }
        # Apply tweaks first
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKCU:\Test\Safe1'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'SafePrivacy1' -Changes $changes -Category 'Privacy'
        Register-AppliedTweak -Name 'SafePrivacy2' -Changes $changes -Category 'Privacy'
        Show-PrivacyMenu -RiskLevel 'safe'
        Should -Invoke Set-PCCleanupRegistry -ParameterFilter { $Value -eq 1 }
    }

    It 'should toggle a specific tweak by number' {
        Mock -CommandName Read-Host -MockWith { '1' }
        Show-PrivacyMenu -RiskLevel 'safe'
        Should -Invoke Set-PCCleanupRegistry -Times 1
    }

    It 'should handle empty category gracefully' {
        # Remove all tweaks from the config
        $emptyTweaks = @{ '_version' = '2.0.0' }
        $emptyTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        $script:SchemaValidated = $false
        Show-PrivacyMenu -RiskLevel 'safe'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No privacy tweaks*' }
    }

    It 'should handle invalid number gracefully' {
        Mock -CommandName Read-Host -MockWith { '99' }
        Show-PrivacyMenu -RiskLevel 'safe'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Invalid number*' }
    }

    It 'should return on B command without action' {
        Mock -CommandName Read-Host -MockWith { 'B' }
        Show-PrivacyMenu -RiskLevel 'safe'
        Should -Invoke Set-PCCleanupRegistry -Times 0
    }
}

Describe 'Show-TweakInfo' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        Mock -CommandName Get-PCCleanupRegistryValue -MockWith {
            [PSCustomObject]@{ Value = 1; Type = 'DWord'; Exists = $true }
        }
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'TestSvc'; StartType = 'Automatic'; Status = 'Running' }
        }

        $script:SchemaValidated = $true
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'

        $script:ConfigPath = $TestDrive
        $testTweaks = @{
            'TestTweak' = @{
                name = 'Test Tweak'
                description = 'Test description'
                detail = 'Detailed explanation of the test tweak'
                docsUrl = 'https://example.com/docs'
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
            'SvcTweak' = @{
                name = 'Service Tweak'
                description = 'Tweak with service'
                detail = 'Detail about service tweak'
                docsUrl = 'https://example.com/svc'
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
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
    }

    It 'should display tweak detail and docsUrl' {
        Show-TweakInfo -Name 'TestTweak'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Detailed explanation*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*https://example.com/docs*' }
    }

    It 'should query current registry state' {
        Show-TweakInfo -Name 'TestTweak'
        Should -Invoke Get-PCCleanupRegistryValue -Times 1
    }

    It 'should query current service state' {
        Show-TweakInfo -Name 'SvcTweak'
        Should -Invoke Get-Service -Times 1 -ParameterFilter { $Name -eq 'TestSvc' }
    }

    It 'should show applied status when tweak is in undo log' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKCU:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'TestTweak' -Changes $changes -Category 'Privacy'
        Show-TweakInfo -Name 'TestTweak'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*APPLIED*' }
    }

    It 'should show not applied status when tweak is not in undo log' {
        Show-TweakInfo -Name 'TestTweak'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Not applied*' }
    }

    It 'should handle tweak not found gracefully' {
        Show-TweakInfo -Name 'NonexistentTweak'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*not found*' }
    }

    It 'should display risk level with color' {
        Show-TweakInfo -Name 'TestTweak'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*safe*' -and $ForegroundColor -eq 'Green' }
    }
}
