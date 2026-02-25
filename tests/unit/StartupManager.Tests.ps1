# ==============================================================================
# PC Cleanup v2 -- StartupManager Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
    . "$PSScriptRoot/../../src/core/04-TweakEngine.ps1"
    . "$PSScriptRoot/../../src/core/05-UndoManager.ps1"
    . "$PSScriptRoot/../../src/core/06-SafeFileOps.ps1"
    . "$PSScriptRoot/../../src/handlers/RegistryHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ServiceHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/TaskHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ScriptHandler.ps1"
    . "$PSScriptRoot/../../src/modules/StartupManager.ps1"
}

Describe 'Resolve-StartupExePath' {
    It 'should extract quoted path' {
        $result = Resolve-StartupExePath -Command '"C:\Program Files\App\app.exe" --arg1'
        $result | Should -Be 'C:\Program Files\App\app.exe'
    }

    It 'should extract unquoted path with exe extension' {
        $result = Resolve-StartupExePath -Command 'C:\App\tool.exe /silent'
        $result | Should -Be 'C:\App\tool.exe'
    }

    It 'should expand environment variables' {
        $result = Resolve-StartupExePath -Command '"%USERPROFILE%\app.exe"'
        $result | Should -Not -Contain '%USERPROFILE%'
        $result | Should -BeLike "*\app.exe"
    }

    It 'should handle paths without arguments' {
        $result = Resolve-StartupExePath -Command 'C:\Simple\app.exe'
        $result | Should -Be 'C:\Simple\app.exe'
    }

    It 'should handle bat files' {
        $result = Resolve-StartupExePath -Command 'C:\Scripts\start.bat /args'
        $result | Should -Be 'C:\Scripts\start.bat'
    }
}

Describe 'Get-StartupFileInfo' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should mark empty paths as orphaned' {
        $result = Get-StartupFileInfo -ExePath ''
        $result.IsOrphaned | Should -BeTrue
    }

    It 'should mark nonexistent paths as orphaned with "(file missing)"' {
        $result = Get-StartupFileInfo -ExePath 'C:\nonexistent\app.exe'
        $result.IsOrphaned | Should -BeTrue
        $result.Description | Should -Be '(file missing)'
    }

    It 'should return publisher and description for valid executables' {
        # Use a known system executable
        $notepad = "$env:SystemRoot\System32\notepad.exe"
        if (Test-Path $notepad) {
            $result = Get-StartupFileInfo -ExePath $notepad
            $result.IsOrphaned | Should -BeFalse
            $result.Publisher | Should -Not -BeNullOrEmpty
        }
        else {
            Set-ItResult -Skipped -Because 'notepad.exe not found'
        }
    }
}

Describe 'Get-StartupClassification' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        $script:ConfigPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'config'
    }

    It 'should load critical apps database' {
        $result = Get-StartupClassification -Type 'critical'
        $result.Count | Should -BeGreaterThan 0
    }

    It 'should load bloat apps database' {
        $result = Get-StartupClassification -Type 'bloat'
        $result.Count | Should -BeGreaterThan 0
    }

    It 'should return entries with required fields' {
        $result = Get-StartupClassification -Type 'critical'
        foreach ($entry in $result) {
            $entry.name | Should -Not -BeNullOrEmpty
            $entry.pattern | Should -Not -BeNullOrEmpty
            $entry.description | Should -Not -BeNullOrEmpty
        }
    }

    It 'should return empty array for missing config file' {
        $script:ConfigPath = Join-Path $TestDrive 'nonexistent_config'
        $result = Get-StartupClassification -Type 'critical'
        @($result).Count | Should -Be 0
    }
}

Describe 'Get-StartupRisk' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should classify critical programs' {
        $critical = @(
            [PSCustomObject]@{ name = 'NVIDIA'; pattern = 'nvcontainer\.exe'; description = 'GPU driver'; severity = 'critical' }
        )
        $result = Get-StartupRisk -Name 'NVIDIA' -ExePath 'C:\nvcontainer.exe' -CriticalList $critical -BloatList @()
        $result.Risk | Should -Be 'critical'
    }

    It 'should classify bloat programs' {
        $bloat = @(
            [PSCustomObject]@{ name = 'Steam'; pattern = 'steam\.exe'; description = 'Gaming platform'; risk = 'safe' }
        )
        $result = Get-StartupRisk -Name 'Steam' -ExePath 'C:\steam.exe' -CriticalList @() -BloatList $bloat
        $result.Risk | Should -Be 'bloat'
    }

    It 'should return normal for unclassified programs' {
        $result = Get-StartupRisk -Name 'CustomApp' -ExePath 'C:\custom.exe' -CriticalList @() -BloatList @()
        $result.Risk | Should -Be 'normal'
    }

    It 'should prioritize critical over bloat' {
        $critical = @(
            [PSCustomObject]@{ name = 'Test'; pattern = 'test\.exe'; description = 'Critical'; severity = 'critical' }
        )
        $bloat = @(
            [PSCustomObject]@{ name = 'Test'; pattern = 'test\.exe'; description = 'Bloat'; risk = 'safe' }
        )
        $result = Get-StartupRisk -Name 'Test' -ExePath 'C:\test.exe' -CriticalList $critical -BloatList $bloat
        $result.Risk | Should -Be 'critical'
    }

    It 'should match on program name as well as exe path' {
        $bloat = @(
            [PSCustomObject]@{ name = 'Discord'; pattern = 'Discord\.exe'; description = 'Chat app'; risk = 'safe' }
        )
        # Name contains the pattern but ExePath doesn't
        $result = Get-StartupRisk -Name 'Discord.exe Startup' -ExePath 'C:\other.exe' -CriticalList @() -BloatList $bloat
        $result.Risk | Should -Be 'bloat'
    }
}

Describe 'Get-StartupPrograms' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        $script:ConfigPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'config'
    }

    It 'should not throw' {
        { Get-StartupPrograms } | Should -Not -Throw
    }

    It 'should return objects with required properties' {
        $result = Get-StartupPrograms
        if ($result.Count -gt 0) {
            $first = $result[0]
            $first.PSObject.Properties.Name | Should -Contain 'Name'
            $first.PSObject.Properties.Name | Should -Contain 'Command'
            $first.PSObject.Properties.Name | Should -Contain 'ExePath'
            $first.PSObject.Properties.Name | Should -Contain 'Publisher'
            $first.PSObject.Properties.Name | Should -Contain 'Source'
            $first.PSObject.Properties.Name | Should -Contain 'Risk'
            $first.PSObject.Properties.Name | Should -Contain 'IsOrphaned'
        }
        else {
            Set-ItResult -Skipped -Because 'No startup programs found on this machine'
        }
    }

    It 'should classify startup programs against critical and bloat lists' {
        $result = Get-StartupPrograms
        foreach ($prog in $result) {
            $prog.Risk | Should -BeIn @('critical', 'bloat', 'normal')
        }
    }
}

Describe 'Disable-StartupProgram' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }

        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
        $script:ConfigPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'config'
    }

    It 'should warn when program is not found' {
        # Mock Get-StartupPrograms to return empty
        Mock -CommandName Get-StartupPrograms -MockWith { @() }

        Disable-StartupProgram -Name 'NonExistentProgram'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*not found*' }
    }

    It 'should register undo data when disabling a registry startup' {
        # Create a test registry entry
        $testRegPath = "HKCU:\SOFTWARE\PCCleanupTest_$(Get-Random)"
        New-Item -Path $testRegPath -Force | Out-Null
        Set-ItemProperty -Path $testRegPath -Name 'TestApp' -Value 'C:\test.exe' -Force

        Mock -CommandName Get-StartupPrograms -MockWith {
            @([PSCustomObject]@{
                Name       = 'TestApp'
                Command    = 'C:\test.exe'
                ExePath    = 'C:\test.exe'
                Publisher  = 'Test'
                Description = 'Test app'
                Source     = 'Registry (User)'
                SourcePath = $testRegPath
                SourceType = 'Registry'
                Risk       = 'normal'
                RiskReason = ''
                IsOrphaned = $false
            })
        }

        Disable-StartupProgram -Name 'TestApp'

        # Verify undo data was registered
        $applied = Get-AppliedTweaks
        @($applied | Where-Object { $_.TweakName -eq 'Startup_TestApp' }).Count | Should -Be 1

        # Cleanup
        Remove-Item -Path $testRegPath -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Enable-StartupProgram' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }

        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
    }

    It 'should warn when no undo data exists' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        '[]' | Set-Content -Path $script:UndoLogPath

        Enable-StartupProgram -Name 'NonExistentProgram'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No undo data*' }
    }

    It 'should restore registry entry from undo data' {
        $testRegPath = "HKCU:\SOFTWARE\PCCleanupTest_$(Get-Random)"
        New-Item -Path $testRegPath -Force | Out-Null

        # Simulate a disable: register undo data
        $changes = @([PSCustomObject]@{
            Type    = 'StartupRegistry'
            Path    = $testRegPath
            Name    = 'RestoredApp'
            Command = 'C:\restored.exe --start'
        })
        Register-AppliedTweak -Name 'Startup_RestoredApp' -Changes $changes -Category 'Startup'

        # Now enable (restore)
        Enable-StartupProgram -Name 'RestoredApp'

        # Verify the registry value was restored
        $val = Get-ItemProperty -Path $testRegPath -Name 'RestoredApp' -ErrorAction SilentlyContinue
        $val.RestoredApp | Should -Be 'C:\restored.exe --start'

        # Cleanup
        Remove-Item -Path $testRegPath -Force -ErrorAction SilentlyContinue
    }

    It 'should remove entry from undo log after successful restore' {
        $testRegPath = "HKCU:\SOFTWARE\PCCleanupTest_$(Get-Random)"
        New-Item -Path $testRegPath -Force | Out-Null

        $changes = @([PSCustomObject]@{
            Type    = 'StartupRegistry'
            Path    = $testRegPath
            Name    = 'CleanupApp'
            Command = 'C:\cleanup.exe'
        })
        Register-AppliedTweak -Name 'Startup_CleanupApp' -Changes $changes -Category 'Startup'

        Enable-StartupProgram -Name 'CleanupApp'

        # Undo log should no longer contain this entry
        $applied = Get-AppliedTweaks
        @($applied | Where-Object { $_.TweakName -eq 'Startup_CleanupApp' }).Count | Should -Be 0

        Remove-Item -Path $testRegPath -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Resolve-ShortcutTarget' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return original path when shortcut cannot be resolved' {
        $result = Resolve-ShortcutTarget -LnkPath 'C:\nonexistent.lnk'
        $result | Should -Be 'C:\nonexistent.lnk'
    }

    It 'should resolve valid shortcut target' {
        # Create a test shortcut pointing to notepad
        $lnkPath = Join-Path $TestDrive 'test.lnk'
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($lnkPath)
        $shortcut.TargetPath = "$env:SystemRoot\System32\notepad.exe"
        $shortcut.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null

        $result = Resolve-ShortcutTarget -LnkPath $lnkPath
        $result | Should -BeLike '*notepad.exe'
    }
}
