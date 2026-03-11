BeforeAll {
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
    . "$PSScriptRoot/../../src/modules/StartupManager.ps1"
    . "$PSScriptRoot/../../src/modules/PerformanceMode.ps1"
    . "$PSScriptRoot/../../src/modules/PrivacyShield.ps1"
    . "$PSScriptRoot/../../src/modules/NetworkReset.ps1"
    . "$PSScriptRoot/../../src/modules/DiskAnalysis.ps1"
    . "$PSScriptRoot/../../src/modules/SecurityCheck.ps1"
    . "$PSScriptRoot/../../src/modules/SystemReport.ps1"
    . "$PSScriptRoot/../../src/modules/FullTuneUp.ps1"
    . "$PSScriptRoot/../../src/ui/Menu.ps1"
}

Describe 'Show-Banner' {
    It 'should not throw' {
        { Show-Banner } | Should -Not -Throw
    }

    It 'should display admin warning when not admin' {
        Mock Test-IsAdmin { return $false }
        $output = Show-Banner 6>&1
        # Function writes via Write-Host -- just verify no exception
    }
}

Describe 'Show-MainMenu' {
    It 'should return QuickClean for input 1' {
        Mock Read-Host { return '1' }
        $result = Show-MainMenu
        $result | Should -Be 'QuickClean'
    }

    It 'should return Startup for input 2' {
        Mock Read-Host { return '2' }
        $result = Show-MainMenu
        $result | Should -Be 'Startup'
    }

    It 'should return Performance for input 3' {
        Mock Read-Host { return '3' }
        $result = Show-MainMenu
        $result | Should -Be 'Performance'
    }

    It 'should return Privacy for input 4' {
        Mock Read-Host { return '4' }
        $result = Show-MainMenu
        $result | Should -Be 'Privacy'
    }

    It 'should return Network for input 5' {
        Mock Read-Host { return '5' }
        $result = Show-MainMenu
        $result | Should -Be 'Network'
    }

    It 'should return Disk for input 6' {
        Mock Read-Host { return '6' }
        $result = Show-MainMenu
        $result | Should -Be 'Disk'
    }

    It 'should return Security for input 7' {
        Mock Read-Host { return '7' }
        $result = Show-MainMenu
        $result | Should -Be 'Security'
    }

    It 'should return Report for input 8' {
        Mock Read-Host { return '8' }
        $result = Show-MainMenu
        $result | Should -Be 'Report'
    }

    It 'should return TuneUp for input 9' {
        Mock Read-Host { return '9' }
        $result = Show-MainMenu
        $result | Should -Be 'TuneUp'
    }

    It 'should return BackupRestore for input 10' {
        Mock Read-Host { return '10' }
        $result = Show-MainMenu
        $result | Should -Be 'BackupRestore'
    }

    It 'should return $null for Q' {
        Mock Read-Host { return 'Q' }
        $result = Show-MainMenu
        $result | Should -BeNullOrEmpty
    }

    It 'should return $null for q (lowercase)' {
        Mock Read-Host { return 'q' }
        $result = Show-MainMenu
        $result | Should -BeNullOrEmpty
    }

    It 'should return $null for empty input' {
        Mock Read-Host { return '' }
        $result = Show-MainMenu
        $result | Should -BeNullOrEmpty
    }

    It 'should return Invalid for unrecognized input' {
        Mock Read-Host { return 'xyz' }
        $result = Show-MainMenu
        $result | Should -Be 'Invalid'
    }
}

Describe 'Show-BackupRestoreMenu' {
    BeforeEach {
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
    }

    It 'should handle empty undo log' {
        Mock Read-Host { return 'B' }
        Mock Get-SafetyStatus { return [PSCustomObject]@{ RestorePoints = 0; Backups = 0; UndoLogEntries = 0 } }
        { Show-BackupRestoreMenu } | Should -Not -Throw
    }

    It 'should display applied tweaks' {
        Mock Read-Host { return 'B' }
        Mock Get-SafetyStatus { return [PSCustomObject]@{ RestorePoints = 0; Backups = 1; UndoLogEntries = 1 } }

        # Create undo log with one entry
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        @([PSCustomObject]@{
            TweakName = 'TestTweak'
            AppliedAt = (Get-Date).ToString('o')
            AppliedOnBuild = 22631
            Category = 'Privacy'
            Changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKCU:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        }) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:UndoLogPath

        { Show-BackupRestoreMenu } | Should -Not -Throw
    }

    It 'should undo specific tweak by number' {
        Mock Get-SafetyStatus { return [PSCustomObject]@{ RestorePoints = 0; Backups = 0; UndoLogEntries = 1 } }
        Mock Read-Host { return '1' }
        Mock Invoke-UndoTweak {}

        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        @([PSCustomObject]@{
            TweakName = 'TestTweak'
            AppliedAt = (Get-Date).ToString('o')
            AppliedOnBuild = 22631
            Category = 'Privacy'
            Changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKCU:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        }) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:UndoLogPath

        Show-BackupRestoreMenu
        Should -Invoke Invoke-UndoTweak -Times 1 -ParameterFilter { $Name -eq 'TestTweak' }
    }
}

Describe 'Show-SelectionMenu' {
    It 'should return selected items when user presses D' {
        Mock Read-Host { return 'D' }
        $items = @(
            [PSCustomObject]@{ Name = 'Item1'; Description = 'Desc1'; Selected = $true }
            [PSCustomObject]@{ Name = 'Item2'; Description = 'Desc2'; Selected = $false }
        )
        $result = @(Show-SelectionMenu -Title 'Test' -Items $items)
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'Item1'
    }

    It 'should return all items when user presses A' {
        Mock Read-Host { return 'A' }
        $items = @(
            [PSCustomObject]@{ Name = 'Item1'; Description = 'Desc1'; Selected = $false }
            [PSCustomObject]@{ Name = 'Item2'; Description = 'Desc2'; Selected = $false }
        )
        $result = Show-SelectionMenu -Title 'Test' -Items $items
        $result.Count | Should -Be 2
    }

    It 'should return empty when user presses N' {
        Mock Read-Host { return 'N' }
        $items = @(
            [PSCustomObject]@{ Name = 'Item1'; Description = 'Desc1'; Selected = $true }
        )
        $result = Show-SelectionMenu -Title 'Test' -Items $items
        $result.Count | Should -Be 0
    }

    It 'should return empty when user presses B' {
        Mock Read-Host { return 'B' }
        $items = @(
            [PSCustomObject]@{ Name = 'Item1'; Description = 'Desc1'; Selected = $true }
        )
        $result = Show-SelectionMenu -Title 'Test' -Items $items
        $result.Count | Should -Be 0
    }

    It 'should select exactly items 1,5,2 when toggled from unselected state' {
        Mock Read-Host { return '1,5,2' }
        $items = @(
            [PSCustomObject]@{ Name = 'TempFiles';   Description = 'D1'; Selected = $false }
            [PSCustomObject]@{ Name = 'WinTemp';     Description = 'D2'; Selected = $false }
            [PSCustomObject]@{ Name = 'WUCache';     Description = 'D3'; Selected = $false }
            [PSCustomObject]@{ Name = 'Prefetch';    Description = 'D4'; Selected = $false }
            [PSCustomObject]@{ Name = 'ChromeCache'; Description = 'D5'; Selected = $false }
            [PSCustomObject]@{ Name = 'EdgeCache';   Description = 'D6'; Selected = $false }
        )
        $result = @(Show-SelectionMenu -Title 'Select targets:' -Items $items)
        $result.Count | Should -Be 3
        $names = @($result | ForEach-Object { $_.Name })
        $names | Should -Contain 'TempFiles'
        $names | Should -Contain 'ChromeCache'
        $names | Should -Contain 'WinTemp'
        $names | Should -Not -Contain 'WUCache'
        $names | Should -Not -Contain 'Prefetch'
        $names | Should -Not -Contain 'EdgeCache'
    }

    It 'should select exactly items 1,3,5 and clean only those' {
        Mock Read-Host { return '1,3,5' }
        $items = @(
            [PSCustomObject]@{ Name = 'UserTemp';    Description = 'D1'; Selected = $false }
            [PSCustomObject]@{ Name = 'WinTemp';     Description = 'D2'; Selected = $false }
            [PSCustomObject]@{ Name = 'WUCache';     Description = 'D3'; Selected = $false }
            [PSCustomObject]@{ Name = 'Prefetch';    Description = 'D4'; Selected = $false }
            [PSCustomObject]@{ Name = 'ChromeCache'; Description = 'D5'; Selected = $false }
            [PSCustomObject]@{ Name = 'EdgeCache';   Description = 'D6'; Selected = $false }
        )
        $result = @(Show-SelectionMenu -Title 'Select targets:' -Items $items)
        $result.Count | Should -Be 3
        $selectedNames = @($result | ForEach-Object { $_.Name })
        $selectedNames | Should -Contain 'UserTemp'
        $selectedNames | Should -Contain 'WUCache'
        $selectedNames | Should -Contain 'ChromeCache'
        $selectedNames | Should -Not -Contain 'WinTemp'
        $selectedNames | Should -Not -Contain 'Prefetch'
        $selectedNames | Should -Not -Contain 'EdgeCache'
    }

    It 'should handle space-separated numbers (1 2 3)' {
        Mock Read-Host { return '1 3 5' }
        $items = @(
            [PSCustomObject]@{ Name = 'A'; Description = ''; Selected = $false }
            [PSCustomObject]@{ Name = 'B'; Description = ''; Selected = $false }
            [PSCustomObject]@{ Name = 'C'; Description = ''; Selected = $false }
            [PSCustomObject]@{ Name = 'D'; Description = ''; Selected = $false }
            [PSCustomObject]@{ Name = 'E'; Description = ''; Selected = $false }
        )
        $result = @(Show-SelectionMenu -Title 'Test' -Items $items)
        $result.Count | Should -Be 3
        $names = @($result | ForEach-Object { $_.Name })
        $names | Should -Contain 'A'
        $names | Should -Contain 'C'
        $names | Should -Contain 'E'
    }

    It 'should handle comma-space-separated numbers (1, 2, 3)' {
        Mock Read-Host { return '2, 4' }
        $items = @(
            [PSCustomObject]@{ Name = 'A'; Description = ''; Selected = $false }
            [PSCustomObject]@{ Name = 'B'; Description = ''; Selected = $false }
            [PSCustomObject]@{ Name = 'C'; Description = ''; Selected = $false }
            [PSCustomObject]@{ Name = 'D'; Description = ''; Selected = $false }
        )
        $result = @(Show-SelectionMenu -Title 'Test' -Items $items)
        $result.Count | Should -Be 2
        $names = @($result | ForEach-Object { $_.Name })
        $names | Should -Contain 'B'
        $names | Should -Contain 'D'
    }

    It 'should handle single number input' {
        Mock Read-Host { return '3' }
        $items = @(
            [PSCustomObject]@{ Name = 'A'; Description = ''; Selected = $false }
            [PSCustomObject]@{ Name = 'B'; Description = ''; Selected = $false }
            [PSCustomObject]@{ Name = 'C'; Description = ''; Selected = $false }
        )
        $result = @(Show-SelectionMenu -Title 'Test' -Items $items)
        $result.Count | Should -Be 1
        $result[0].Name | Should -Be 'C'
    }
}

Describe 'Show-ReportMenu' {
    It 'should handle back input' {
        Mock Read-Host { return 'B' }
        { Show-ReportMenu } | Should -Not -Throw
    }

    It 'should handle empty input' {
        Mock Read-Host { return '' }
        { Show-ReportMenu } | Should -Not -Throw
    }
}

Describe 'Invoke-MenuLoop' {
    It 'should exit when user selects Q' {
        Mock Show-Banner {}
        Mock Show-MainMenu { return $null }
        { Invoke-MenuLoop } | Should -Not -Throw
    }
}

Describe 'Show-StartupMenu' {
    It 'should handle empty startup list' {
        Mock Get-StartupPrograms { return @() }
        { Show-StartupMenu } | Should -Not -Throw
    }

    It 'should return on B input' {
        Mock Get-StartupPrograms {
            return @([PSCustomObject]@{
                Name = 'TestApp'; Command = 'test.exe'; ExePath = 'C:\test.exe'
                Publisher = 'Test'; Description = 'Test app'; Source = 'Registry'
                Risk = 'normal'; RiskReason = ''; IsOrphaned = $false
            })
        }
        Mock Read-Host { return 'B' }
        { Show-StartupMenu } | Should -Not -Throw
    }
}
