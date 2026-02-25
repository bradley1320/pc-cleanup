# ==============================================================================
# PC Cleanup v2 -- PerformanceMode Tests (Pester 5.x)
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
    . "$PSScriptRoot/../../src/modules/PerformanceMode.ps1"
}

Describe 'Show-PerformanceMenu' {
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
        Mock -CommandName Get-ChassisType -MockWith { 'Desktop' }
        Mock -CommandName Test-IsSSD -MockWith { $true }
        Mock -CommandName Send-SettingChange -MockWith { $true }
        Mock -CommandName Stop-Process -MockWith {}
        Mock -CommandName Start-Process -MockWith {}

        $script:SchemaValidated = $true
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
        $script:ConfigPath = $TestDrive

        $testTweaks = @{
            '_version' = '2.0.0'
            'SafePerf1' = @{
                name = 'Safe Performance 1'
                description = 'First safe perf tweak'
                detail = 'Detail about safe perf 1'
                docsUrl = 'https://example.com/perf1'
                category = 'Performance'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test\Perf1'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'OptimizeVisualEffects' = @{
                name = 'Optimize Visual Effects'
                description = 'Visual effects optimization'
                detail = 'Detail about visual effects'
                docsUrl = 'https://example.com/visual'
                category = 'Performance'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test\Visual'; name = 'Val'; value = 2; type = 'DWord'; defaultValue = 0 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
            'ModeratePerf1' = @{
                name = 'Moderate Performance 1'
                description = 'A moderate perf tweak'
                detail = 'Detail about moderate perf'
                docsUrl = 'https://example.com/modperf'
                category = 'Performance'
                risk = 'moderate'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $true
                registry = @()
                services = @(@{ name = 'WSearch'; startupType = 'Disabled'; defaultType = 'Automatic' })
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $testTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
    }

    It 'should load only Performance category tweaks' {
        Show-PerformanceMenu -RiskLevel 'safe'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Safe Performance*' }
    }

    It 'should respect risk level parameter' {
        Show-PerformanceMenu -RiskLevel 'safe'
        Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -like '*Moderate Performance*' }
    }

    It 'should show moderate tweaks when risk level is moderate' {
        Show-PerformanceMenu -RiskLevel 'moderate'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Moderate Performance*' }
    }

    It 'should display tier headers' {
        Show-PerformanceMenu -RiskLevel 'moderate'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*SAFE TIER*' }
    }

    It 'should show applied status from undo log' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKCU:\Test\Perf1'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'SafePerf1' -Changes $changes -Category 'Performance'
        Show-PerformanceMenu -RiskLevel 'safe'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*`[X`]*Safe Performance 1*' }
    }

    It 'should apply all unapplied tweaks on A command' {
        Mock -CommandName Read-Host -MockWith { 'A' }
        Show-PerformanceMenu -RiskLevel 'safe'
        Should -Invoke Set-PCCleanupRegistry -Times 2
    }

    It 'should undo all applied tweaks on U command' {
        Mock -CommandName Read-Host -MockWith { 'U' }
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKCU:\Test\Perf1'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'SafePerf1' -Changes $changes -Category 'Performance'
        Register-AppliedTweak -Name 'OptimizeVisualEffects' -Changes $changes -Category 'Performance'
        Show-PerformanceMenu -RiskLevel 'safe'
        Should -Invoke Set-PCCleanupRegistry -ParameterFilter { $Value -eq 1 }
    }

    It 'should toggle a specific tweak by number' {
        Mock -CommandName Read-Host -MockWith { '1' }
        Show-PerformanceMenu -RiskLevel 'safe'
        Should -Invoke Set-PCCleanupRegistry -Times 1
    }

    It 'should return on B command without action' {
        Mock -CommandName Read-Host -MockWith { 'B' }
        Show-PerformanceMenu -RiskLevel 'safe'
        Should -Invoke Set-PCCleanupRegistry -Times 0
    }

    It 'should handle empty category gracefully' {
        $emptyTweaks = @{ '_version' = '2.0.0' }
        $emptyTweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        $script:SchemaValidated = $false
        Show-PerformanceMenu -RiskLevel 'safe'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No performance tweaks*' }
    }

    It 'should handle invalid number gracefully' {
        Mock -CommandName Read-Host -MockWith { '99' }
        Show-PerformanceMenu -RiskLevel 'safe'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Invalid number*' }
    }

    It 'should trigger Explorer refresh after applying visual tweaks' {
        Mock -CommandName Read-Host -MockWith { 'A' }
        Show-PerformanceMenu -RiskLevel 'safe'
        Should -Invoke Send-SettingChange -Times 1
    }

    It 'should trigger Explorer refresh after undoing visual tweaks' {
        Mock -CommandName Read-Host -MockWith { 'U' }
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKCU:\Test\Visual'; Name = 'Val'; OriginalValue = 0; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'OptimizeVisualEffects' -Changes $changes -Category 'Performance'
        Show-PerformanceMenu -RiskLevel 'safe'
        Should -Invoke Send-SettingChange -Times 1
    }
}

Describe 'Show-SystemWarnings' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should warn on laptop' {
        Mock -CommandName Get-ChassisType -MockWith { 'Laptop' }
        Mock -CommandName Test-IsSSD -MockWith { $true }
        Show-SystemWarnings
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Laptop detected*' }
    }

    It 'should not warn on desktop' {
        Mock -CommandName Get-ChassisType -MockWith { 'Desktop' }
        Mock -CommandName Test-IsSSD -MockWith { $true }
        Show-SystemWarnings
        Should -Invoke Write-Host -Times 0 -ParameterFilter { $Object -like '*Laptop detected*' }
    }

    It 'should note HDD detection' {
        Mock -CommandName Get-ChassisType -MockWith { 'Desktop' }
        Mock -CommandName Test-IsSSD -MockWith { $false }
        Show-SystemWarnings
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*HDD detected*' }
    }

    It 'should handle SSD detection failure gracefully' {
        Mock -CommandName Get-ChassisType -MockWith { 'Desktop' }
        Mock -CommandName Test-IsSSD -MockWith { throw 'CIM error' }
        { Show-SystemWarnings } | Should -Not -Throw
    }
}

Describe 'Invoke-ExplorerRefresh' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should succeed when P/Invoke works' {
        Mock -CommandName Send-SettingChange -MockWith { $true }
        Invoke-ExplorerRefresh
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Shell refreshed*' }
    }

    It 'should offer Explorer restart when P/Invoke fails and user declines' {
        Mock -CommandName Send-SettingChange -MockWith { $false }
        Mock -CommandName Get-UserConfirmation -MockWith { $false }
        Invoke-ExplorerRefresh
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*log out*' }
    }

    It 'should restart Explorer when P/Invoke fails and user accepts' {
        Mock -CommandName Send-SettingChange -MockWith { $false }
        Mock -CommandName Get-UserConfirmation -MockWith { $true }
        Mock -CommandName Stop-Process -MockWith {}
        Mock -CommandName Start-Process -MockWith {}
        Invoke-ExplorerRefresh
        Should -Invoke Stop-Process -Times 1
        Should -Invoke Start-Process -Times 1
    }
}

Describe 'Send-SettingChange' {
    BeforeEach {
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should not throw on invocation' {
        # P/Invoke may or may not work depending on test environment
        { Send-SettingChange } | Should -Not -Throw
    }

    It 'should return a boolean' {
        $result = Send-SettingChange
        $result | Should -BeOfType [bool]
    }
}
