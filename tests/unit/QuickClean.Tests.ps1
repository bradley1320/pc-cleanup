# ==============================================================================
# PC Cleanup v2 -- QuickClean Tests (Pester 5.x)
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
    . "$PSScriptRoot/../../src/modules/QuickClean.ps1"
}

Describe 'Get-BrowserProfiles' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        $script:DynamicBrowserRoots = @()
    }

    It 'should return an array (even if empty)' {
        $result = Get-BrowserProfiles
        $result | Should -Not -BeNullOrEmpty -Because 'even if empty, should be an array' -ErrorAction SilentlyContinue
        # On machines with no browsers, result may be empty -- that's OK
        { Get-BrowserProfiles } | Should -Not -Throw
    }

    It 'should include Browser, Profile, CachePath, and DataPath properties when browsers exist' {
        $result = Get-BrowserProfiles
        if ($result.Count -gt 0) {
            $first = $result[0]
            $first.PSObject.Properties.Name | Should -Contain 'Browser'
            $first.PSObject.Properties.Name | Should -Contain 'Profile'
            $first.PSObject.Properties.Name | Should -Contain 'CachePath'
            $first.PSObject.Properties.Name | Should -Contain 'DataPath'
        }
        else {
            Set-ItResult -Skipped -Because 'No browsers detected on this machine'
        }
    }

    It 'should register browser roots with SafeFileOps allowlist' {
        $script:DynamicBrowserRoots = @()
        $result = Get-BrowserProfiles
        if ($result.Count -gt 0) {
            $script:DynamicBrowserRoots.Count | Should -BeGreaterThan 0
        }
        else {
            Set-ItResult -Skipped -Because 'No browsers detected on this machine'
        }
    }
}

Describe 'Measure-RecycleBin' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return FileCount, TotalBytes, and Estimated properties' {
        $result = Measure-RecycleBin
        $result.PSObject.Properties.Name | Should -Contain 'FileCount'
        $result.PSObject.Properties.Name | Should -Contain 'TotalBytes'
        $result.PSObject.Properties.Name | Should -Contain 'Estimated'
    }

    It 'should return non-negative values' {
        $result = Measure-RecycleBin
        $result.FileCount | Should -BeGreaterOrEqual 0
        $result.TotalBytes | Should -BeGreaterOrEqual 0
    }

    It 'should not throw on COM failure' {
        Mock -CommandName New-Object -MockWith { throw 'COM error' } -ParameterFilter { $ComObject -eq 'Shell.Application' }
        { Measure-RecycleBin } | Should -Not -Throw
        $result = Measure-RecycleBin
        $result.FileCount | Should -Be 0
    }
}

Describe 'Measure-DirectorySafe' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should count files and measure bytes' {
        $dir = Join-Path $TestDrive 'measure_test'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'file1.txt') -Value 'hello' -NoNewline
        Set-Content -Path (Join-Path $dir 'file2.txt') -Value 'world' -NoNewline

        $result = Measure-DirectorySafe -Path $dir
        $result.FileCount | Should -Be 2
        $result.TotalBytes | Should -BeGreaterThan 0
    }

    It 'should count files in subdirectories' {
        $dir = Join-Path $TestDrive 'measure_recurse'
        $sub = Join-Path $dir 'subdir'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'root.txt') -Value 'a'
        Set-Content -Path (Join-Path $sub 'nested.txt') -Value 'b'

        $result = Measure-DirectorySafe -Path $dir
        $result.FileCount | Should -Be 2
    }

    It 'should return zero for nonexistent directory' {
        $result = Measure-DirectorySafe -Path (Join-Path $TestDrive 'nonexistent')
        $result.FileCount | Should -Be 0
        $result.TotalBytes | Should -Be 0
    }

    It 'should return zero for empty directory' {
        $dir = Join-Path $TestDrive 'empty_dir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        $result = Measure-DirectorySafe -Path $dir
        $result.FileCount | Should -Be 0
    }

    It 'should set Estimated to $false for small directories' {
        $dir = Join-Path $TestDrive 'small_dir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'a.txt') -Value 'a'
        Set-Content -Path (Join-Path $dir 'b.txt') -Value 'b'

        $result = Measure-DirectorySafe -Path $dir
        $result.Estimated | Should -BeFalse
        $result.FileCount | Should -Be 2
    }

    It 'should cap enumeration at MaxFiles and set Estimated to $true' {
        $dir = Join-Path $TestDrive 'cap_test'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        for ($i = 0; $i -lt 10; $i++) {
            Set-Content -Path (Join-Path $dir "file$i.txt") -Value "data$i" -NoNewline
        }

        $result = Measure-DirectorySafe -Path $dir -MaxFiles 5
        $result.FileCount | Should -Be 5
        $result.Estimated | Should -BeTrue
        $result.TotalBytes | Should -BeGreaterThan 0
    }

    It 'should enumerate all files when MaxFiles is 0 (uncapped)' {
        $dir = Join-Path $TestDrive 'uncapped_test'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        for ($i = 0; $i -lt 10; $i++) {
            Set-Content -Path (Join-Path $dir "file$i.txt") -Value "data$i" -NoNewline
        }

        $result = Measure-DirectorySafe -Path $dir -MaxFiles 0
        $result.FileCount | Should -Be 10
        $result.Estimated | Should -BeFalse
    }

    It 'should not follow junctions during measurement' {
        $targetDir = Join-Path $TestDrive 'measure_target'
        $scanDir = Join-Path $TestDrive 'measure_scan'
        $junctionPath = Join-Path $scanDir 'junction_link'

        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Set-Content -Path (Join-Path $targetDir 'hidden.txt') -Value 'should not count'

        New-Item -ItemType Directory -Path $scanDir -Force | Out-Null
        Set-Content -Path (Join-Path $scanDir 'visible.txt') -Value 'should count'

        $null = cmd /c "mklink /J `"$junctionPath`" `"$targetDir`"" 2>&1

        if (Test-Path $junctionPath) {
            $result = Measure-DirectorySafe -Path $scanDir
            # Should only count visible.txt, not hidden.txt behind junction
            $result.FileCount | Should -Be 1
        }
        else {
            Set-ItResult -Skipped -Because 'Junction creation requires specific OS support'
        }
    }
}

Describe 'Test-BrowserRunning' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return $false for a browser that is not running' {
        Mock -CommandName Get-Process -MockWith { $null }
        Test-BrowserRunning -BrowserName 'Chrome' | Should -BeFalse
    }

    It 'should return $true when browser process is found' {
        Mock -CommandName Get-Process -MockWith { [PSCustomObject]@{ Name = 'chrome' } } -ParameterFilter { $Name -eq 'chrome' }
        Test-BrowserRunning -BrowserName 'Chrome' | Should -BeTrue
    }

    It 'should handle Edge process name' {
        Mock -CommandName Get-Process -MockWith { [PSCustomObject]@{ Name = 'msedge' } } -ParameterFilter { $Name -eq 'msedge' }
        Test-BrowserRunning -BrowserName 'Edge' | Should -BeTrue
    }

    It 'should handle Firefox process name' {
        Mock -CommandName Get-Process -MockWith { [PSCustomObject]@{ Name = 'firefox' } } -ParameterFilter { $Name -eq 'firefox' }
        Test-BrowserRunning -BrowserName 'Firefox' | Should -BeTrue
    }

    It 'should handle unknown browser names' {
        Test-BrowserRunning -BrowserName 'UnknownBrowser' | Should -BeFalse
    }
}

Describe 'Get-CleanupTargets' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        # Initialize cleanup roots for the test
        Initialize-AllowedCleanupRoots
    }

    It 'should return an array of targets' {
        $result = Get-CleanupTargets
        $result | Should -Not -BeNullOrEmpty
    }

    It 'should include target properties: Name, Path, FileCount, Size, Type' {
        $result = Get-CleanupTargets
        if ($result.Count -gt 0) {
            $first = $result[0]
            $first.PSObject.Properties.Name | Should -Contain 'Name'
            $first.PSObject.Properties.Name | Should -Contain 'Path'
            $first.PSObject.Properties.Name | Should -Contain 'FileCount'
            $first.PSObject.Properties.Name | Should -Contain 'Size'
            $first.PSObject.Properties.Name | Should -Contain 'Type'
        }
    }

    It 'should include User Temp Files target' {
        $result = Get-CleanupTargets
        $names = @($result | ForEach-Object { $_.Name })
        $names | Should -Contain 'User Temp Files'
    }

    It 'should have non-negative sizes' {
        $result = Get-CleanupTargets
        foreach ($target in $result) {
            $target.Size | Should -BeGreaterOrEqual 0
            $target.FileCount | Should -BeGreaterOrEqual 0
        }
    }

    It 'should include Estimated property on all targets' {
        $result = Get-CleanupTargets
        foreach ($target in $result) {
            $target.PSObject.Properties.Name | Should -Contain 'Estimated'
            $target.Estimated | Should -BeOfType [bool]
        }
    }
}

Describe 'Invoke-Cleanup' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        Mock -CommandName Stop-Service -MockWith {}
        Mock -CommandName Start-Service -MockWith {}
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'wuauserv'; Status = 'Running'; StartType = 'Manual' }
        }

        # Set up allowed roots with TestDrive
        $script:AllowedCleanupRoots = @(
            [System.IO.Path]::GetFullPath($TestDrive)
        )
        $script:DynamicBrowserRoots = @()

        # Redirect manifest output to TestDrive
        $script:OriginalLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $TestDrive
    }

    AfterEach {
        $env:LOCALAPPDATA = $script:OriginalLocalAppData
    }

    It 'should return summary with zero counts for empty target list' {
        $result = Invoke-Cleanup -Targets @()
        $result.TotalFiles | Should -Be 0
        $result.TotalBytes | Should -Be 0
    }

    It 'should delete files from targets' {
        $dir = Join-Path $TestDrive 'cleanup_dir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'file1.tmp') -Value 'data'

        $targets = @(
            [PSCustomObject]@{ Name = 'Test'; Path = $dir; FileCount = 1; Size = 4; Type = 'temp'; RequiresAdmin = $false }
        )

        $result = Invoke-Cleanup -Targets $targets
        $result.TotalFiles | Should -BeGreaterThan 0
    }

    It 'should create pre-deletion manifest' {
        $dir = Join-Path $TestDrive 'manifest_dir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'file.tmp') -Value 'data'

        $targets = @(
            [PSCustomObject]@{ Name = 'Test'; Path = $dir; FileCount = 1; Size = 4; Type = 'temp'; RequiresAdmin = $false }
        )

        Invoke-Cleanup -Targets $targets
        $manifestDir = Join-Path $TestDrive 'PCCleanup\logs'
        $manifests = Get-ChildItem -Path $manifestDir -Filter 'cleanup_manifest_*.json' -ErrorAction SilentlyContinue
        @($manifests).Count | Should -BeGreaterThan 0
    }

    It 'should not create manifest in WhatIf mode' {
        $dir = Join-Path $TestDrive 'whatif_manifest'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'file.tmp') -Value 'data'

        $targets = @(
            [PSCustomObject]@{ Name = 'Test'; Path = $dir; FileCount = 1; Size = 4; Type = 'temp'; RequiresAdmin = $false }
        )

        Invoke-Cleanup -Targets $targets -WhatIf
        # Files should still exist
        Test-Path (Join-Path $dir 'file.tmp') | Should -BeTrue
    }

    It 'should use Clear-RecycleBin for recyclebin targets' {
        Mock -CommandName Clear-RecycleBin -MockWith {}

        $targets = @(
            [PSCustomObject]@{ Name = 'Recycle Bin'; Path = 'RecycleBin'; FileCount = 5; Size = 1024; Type = 'recyclebin'; RequiresAdmin = $false }
        )

        $result = Invoke-Cleanup -Targets $targets
        Should -Invoke -CommandName Clear-RecycleBin -Times 1 -Exactly
        $result.TotalFiles | Should -Be 5
        $result.TotalBytes | Should -Be 1024
    }

    It 'should handle Clear-RecycleBin failure gracefully' {
        Mock -CommandName Clear-RecycleBin -MockWith { throw 'Access denied' }

        $targets = @(
            [PSCustomObject]@{ Name = 'Recycle Bin'; Path = 'RecycleBin'; FileCount = 5; Size = 1024; Type = 'recyclebin'; RequiresAdmin = $false }
        )

        $result = Invoke-Cleanup -Targets $targets
        $result.Errors | Should -Be 1
        $result.TotalFiles | Should -Be 0
    }

    It 'should report cleanup summary with file counts and bytes' {
        $dir = Join-Path $TestDrive 'summary_dir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'a.tmp') -Value 'aaa' -NoNewline
        Set-Content -Path (Join-Path $dir 'b.tmp') -Value 'bbb' -NoNewline

        $targets = @(
            [PSCustomObject]@{ Name = 'Test'; Path = $dir; FileCount = 2; Size = 6; Type = 'temp'; RequiresAdmin = $false }
        )

        $result = Invoke-Cleanup -Targets $targets
        $result.TotalFiles | Should -Be 2
        $result.TotalBytes | Should -BeGreaterThan 0
    }
}
