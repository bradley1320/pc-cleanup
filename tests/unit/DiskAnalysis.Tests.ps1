BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/modules/DiskAnalysis.ps1"
}

Describe 'Get-DriveUsage' {
    It 'should return an array of drive objects' {
        $drives = Get-DriveUsage
        $drives | Should -Not -BeNullOrEmpty
    }

    It 'should include required properties' {
        $drives = Get-DriveUsage
        if ($drives.Count -gt 0) {
            $drives[0].PSObject.Properties.Name | Should -Contain 'Drive'
            $drives[0].PSObject.Properties.Name | Should -Contain 'TotalBytes'
            $drives[0].PSObject.Properties.Name | Should -Contain 'UsedBytes'
            $drives[0].PSObject.Properties.Name | Should -Contain 'FreeBytes'
            $drives[0].PSObject.Properties.Name | Should -Contain 'PctUsed'
        }
    }

    It 'should have non-negative byte counts' {
        $drives = Get-DriveUsage
        foreach ($drive in $drives) {
            $drive.TotalBytes | Should -BeGreaterOrEqual 0
            $drive.UsedBytes | Should -BeGreaterOrEqual 0
            $drive.FreeBytes | Should -BeGreaterOrEqual 0
        }
    }

    It 'should have percentage between 0 and 100' {
        $drives = Get-DriveUsage
        foreach ($drive in $drives) {
            $drive.PctUsed | Should -BeGreaterOrEqual 0
            $drive.PctUsed | Should -BeLessOrEqual 100
        }
    }

    It 'should include system drive' {
        $drives = Get-DriveUsage
        $systemDrive = ($env:SystemDrive).TrimEnd('\')
        $hasSysDrive = @($drives | Where-Object { $_.Drive -eq $systemDrive }).Count -gt 0
        $hasSysDrive | Should -Be $true
    }
}

Describe 'Get-FolderSizes' {
    BeforeEach {
        # Create test directory structure
        $testRoot = Join-Path $TestDrive 'foldertest'
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

        $bigDir = Join-Path $testRoot 'BigDir'
        New-Item -ItemType Directory -Path $bigDir -Force | Out-Null
        Set-Content -Path (Join-Path $bigDir 'file1.txt') -Value ('x' * 1000)
        Set-Content -Path (Join-Path $bigDir 'file2.txt') -Value ('y' * 2000)

        $smallDir = Join-Path $testRoot 'SmallDir'
        New-Item -ItemType Directory -Path $smallDir -Force | Out-Null
        Set-Content -Path (Join-Path $smallDir 'tiny.txt') -Value 'hello'

        $emptyDir = Join-Path $testRoot 'EmptyDir'
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null
    }

    It 'should return folder objects with required properties' {
        $folders = Get-FolderSizes -Path (Join-Path $TestDrive 'foldertest')
        $folders | Should -Not -BeNullOrEmpty
        $folders[0].PSObject.Properties.Name | Should -Contain 'Path'
        $folders[0].PSObject.Properties.Name | Should -Contain 'Name'
        $folders[0].PSObject.Properties.Name | Should -Contain 'Size'
        $folders[0].PSObject.Properties.Name | Should -Contain 'FileCount'
    }

    It 'should sort by size descending' {
        $folders = Get-FolderSizes -Path (Join-Path $TestDrive 'foldertest')
        if ($folders.Count -ge 2) {
            $folders[0].Size | Should -BeGreaterOrEqual $folders[1].Size
        }
    }

    It 'should count files correctly' {
        $folders = Get-FolderSizes -Path (Join-Path $TestDrive 'foldertest')
        $bigFolder = $folders | Where-Object { $_.Name -eq 'BigDir' }
        $bigFolder | Should -Not -BeNullOrEmpty
        $bigFolder.FileCount | Should -Be 2
    }

    It 'should handle empty directories' {
        $folders = Get-FolderSizes -Path (Join-Path $TestDrive 'foldertest')
        $emptyFolder = $folders | Where-Object { $_.Name -eq 'EmptyDir' }
        $emptyFolder | Should -Not -BeNullOrEmpty
        $emptyFolder.Size | Should -Be 0
        $emptyFolder.FileCount | Should -Be 0
    }

    It 'should return empty array for nonexistent path' {
        $folders = Get-FolderSizes -Path (Join-Path $TestDrive 'nonexistent')
        $folders.Count | Should -Be 0
    }

    It 'should respect depth parameter' {
        # Create nested structure deeper than depth
        $deepRoot = Join-Path $TestDrive 'deeptest'
        $level1 = Join-Path $deepRoot 'L1'
        $level2 = Join-Path $level1 'L2'
        $level3 = Join-Path $level2 'L3'
        $level4 = Join-Path $level3 'L4'

        New-Item -ItemType Directory -Path $level4 -Force | Out-Null
        Set-Content -Path (Join-Path $level4 'deep.txt') -Value 'deep file content'

        # Depth 1 should NOT include L4's file in L1's count (it's at depth 4)
        $folders = Get-FolderSizes -Path $deepRoot -Depth 1
        $l1 = $folders | Where-Object { $_.Name -eq 'L1' }
        $l1 | Should -Not -BeNullOrEmpty

        # With depth 1, we scan L1 (level 0) and L2 (level 1) but not L3 or L4
        # So files in L4 should not be counted
        $l1.FileCount | Should -Be 0
    }

    It 'should not follow junctions' {
        $junctionRoot = Join-Path $TestDrive 'junctiontest'
        $realDir = Join-Path $junctionRoot 'real'
        $targetDir = Join-Path $TestDrive 'junctiontarget'

        New-Item -ItemType Directory -Path $realDir -Force | Out-Null
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Set-Content -Path (Join-Path $targetDir 'secret.txt') -Value 'should not be counted'

        try {
            cmd /c mklink /J "$junctionRoot\linked" "$targetDir" 2>&1 | Out-Null
        }
        catch {
            return
        }

        $folders = Get-FolderSizes -Path $junctionRoot
        $linkedFolder = $folders | Where-Object { $_.Name -eq 'linked' }

        # Junction should either be skipped entirely (not in results)
        # or have 0 size (not following the junction target)
        if ($linkedFolder) {
            $linkedFolder.Size | Should -Be 0
        }
    }
}

Describe 'Show-DriveUsage' {
    It 'should not throw' {
        { Show-DriveUsage } | Should -Not -Throw
    }
}

Describe 'Show-DiskAnalysisMenu' {
    It 'should return without error when user presses B' {
        Mock Read-Host { return 'B' }
        { Show-DiskAnalysisMenu } | Should -Not -Throw
    }

    It 'should return without error when user presses Enter' {
        Mock Read-Host { return '' }
        { Show-DiskAnalysisMenu } | Should -Not -Throw
    }
}
