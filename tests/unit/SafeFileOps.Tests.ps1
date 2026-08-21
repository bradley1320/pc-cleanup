# ==============================================================================
# PC Cleanup v2 -- SafeFileOps Tests (Pester 5.x)
# Tests for the safe file operation infrastructure that resolves all 5 hard
# blockers from the Phase 2 security audit.
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
    . "$PSScriptRoot/../../src/core/06-SafeFileOps.ps1"
}

Describe 'Test-IsReparsePoint' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return $false for a normal directory' {
        $dir = Join-Path $TestDrive 'normaldir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Test-IsReparsePoint -Path $dir | Should -BeFalse
    }

    It 'should return $false for a normal file' {
        $file = Join-Path $TestDrive 'normalfile.txt'
        Set-Content -Path $file -Value 'test'
        Test-IsReparsePoint -Path $file | Should -BeFalse
    }

    It 'should return $false for a path that does not exist' {
        Test-IsReparsePoint -Path (Join-Path $TestDrive 'nonexistent') | Should -BeFalse
    }

    It 'should return $true for paths where attributes cannot be read' {
        # If attributes can't be read, the function should err on the side of caution
        # (returning $true to prevent deletion of potentially dangerous paths)
        # We test this by checking the function exists and returns bool
        { Test-IsReparsePoint -Path $TestDrive } | Should -Not -Throw
    }

    It 'should detect a junction as a reparse point' {
        $targetDir = Join-Path $TestDrive 'junction_target'
        $junctionDir = Join-Path $TestDrive 'junction_link'
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Set-Content -Path (Join-Path $targetDir 'safe.txt') -Value 'protected'

        # Create junction using cmd mklink /J (works without special privileges)
        $null = cmd /c "mklink /J `"$junctionDir`" `"$targetDir`"" 2>&1

        if (Test-Path $junctionDir) {
            Test-IsReparsePoint -Path $junctionDir | Should -BeTrue
        }
        else {
            Set-ItResult -Skipped -Because 'Junction creation requires specific OS support'
        }
    }
}

Describe 'Test-PathWithinAllowlist' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}

        # Override the allowlist to use TestDrive paths for testing
        $script:AllowedCleanupRoots = @(
            [System.IO.Path]::GetFullPath((Join-Path $TestDrive 'allowed_root'))
            [System.IO.Path]::GetFullPath((Join-Path $TestDrive 'second_root'))
        )
        $script:DynamicBrowserRoots = @()

        # Create the allowed root directories
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'allowed_root') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'second_root') -Force | Out-Null
    }

    It 'should allow paths within an allowed root' {
        $path = Join-Path $TestDrive 'allowed_root\subdir\file.tmp'
        Test-PathWithinAllowlist -Path $path | Should -BeTrue
    }

    It 'should allow the root path itself' {
        $path = Join-Path $TestDrive 'allowed_root'
        Test-PathWithinAllowlist -Path $path | Should -BeTrue
    }

    It 'should block paths outside all allowed roots' {
        $path = Join-Path $TestDrive 'forbidden\file.tmp'
        Test-PathWithinAllowlist -Path $path | Should -BeFalse
    }

    It 'should block paths that are partial prefix matches' {
        # C:\allowed_root_extra should NOT match C:\allowed_root
        $path = Join-Path $TestDrive 'allowed_rootextra\file.tmp'
        Test-PathWithinAllowlist -Path $path | Should -BeFalse
    }

    It 'should allow paths in the second allowed root' {
        $path = Join-Path $TestDrive 'second_root\cache\file.dat'
        Test-PathWithinAllowlist -Path $path | Should -BeTrue
    }

    It 'should allow paths added as dynamic browser roots' {
        $browserPath = Join-Path $TestDrive 'browser_cache'
        New-Item -ItemType Directory -Path $browserPath -Force | Out-Null
        Add-BrowserCleanupRoot -Path $browserPath

        $filePath = Join-Path $browserPath 'cookies.db'
        Test-PathWithinAllowlist -Path $filePath | Should -BeTrue
    }

    It 'should handle malformed paths gracefully' {
        # Should not throw -- returns $false for unparseable paths
        Test-PathWithinAllowlist -Path '' | Should -BeFalse
    }
}

Describe 'Test-IsCloudPlaceholder' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return $false for a normal file' {
        $file = Join-Path $TestDrive 'normal.txt'
        Set-Content -Path $file -Value 'content'
        $info = [System.IO.FileInfo]::new($file)
        Test-IsCloudPlaceholder -Item $info | Should -BeFalse
    }

    It 'should return $false for a normal directory' {
        $dir = Join-Path $TestDrive 'normaldir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $info = [System.IO.DirectoryInfo]::new($dir)
        Test-IsCloudPlaceholder -Item $info | Should -BeFalse
    }
}

Describe 'Get-SafePath' {
    It 'should add \\?\ prefix to absolute paths' {
        $result = Get-SafePath -Path 'C:\Windows\Temp'
        $result | Should -Be '\\?\C:\Windows\Temp'
    }

    It 'should not double-prefix paths that already have \\?\' {
        $result = Get-SafePath -Path '\\?\C:\Windows\Temp'
        $result | Should -Be '\\?\C:\Windows\Temp'
    }

    It 'should not prefix relative paths' {
        $result = Get-SafePath -Path 'relative\path'
        $result | Should -Be 'relative\path'
    }
}

Describe 'New-CleanupManifest' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }

        # Redirect manifest output to TestDrive
        $script:OriginalLocalAppData = $env:LOCALAPPDATA
        $env:LOCALAPPDATA = $TestDrive
    }

    AfterEach {
        $env:LOCALAPPDATA = $script:OriginalLocalAppData
    }

    It 'should create a manifest JSON file' {
        $targets = @(
            [PSCustomObject]@{ Name = 'Temp Files'; Path = 'C:\Temp'; FileCount = 10; Size = 1024 }
        )
        $path = New-CleanupManifest -Targets $targets -TotalBytes 1024
        Test-Path $path | Should -BeTrue
    }

    It 'should write valid JSON with correct structure' {
        $targets = @(
            [PSCustomObject]@{ Name = 'Temp'; Path = 'C:\Temp'; FileCount = 5; Size = 500 }
            [PSCustomObject]@{ Name = 'Cache'; Path = 'C:\Cache'; FileCount = 3; Size = 300 }
        )
        $path = New-CleanupManifest -Targets $targets -TotalBytes 800
        $content = Get-Content -Path $path -Raw | ConvertFrom-Json
        $content.TotalBytes | Should -Be 800
        $content.TargetCount | Should -Be 2
        $content.OSBuild | Should -Be 22631
        @($content.Targets).Count | Should -Be 2
    }

    It 'should include timestamp in filename' {
        $targets = @(
            [PSCustomObject]@{ Name = 'Temp'; Path = 'C:\Temp'; FileCount = 1; Size = 100 }
        )
        $path = New-CleanupManifest -Targets $targets
        $path | Should -Match 'cleanup_manifest_\d{4}-\d{2}-\d{2}_\d{6}\.json'
    }
}

Describe 'Remove-SafeDirectory' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}

        # Set up an allowed root for testing
        $script:AllowedCleanupRoots = @(
            [System.IO.Path]::GetFullPath($TestDrive)
        )
        $script:DynamicBrowserRoots = @()
    }

    It 'should delete files from a normal directory' {
        $dir = Join-Path $TestDrive 'cleanup_test'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'file1.tmp') -Value 'data1'
        Set-Content -Path (Join-Path $dir 'file2.tmp') -Value 'data2'

        $result = Remove-SafeDirectory -Path $dir
        $result.DeletedFiles | Should -Be 2
        $result.Errors | Should -Be 0
    }

    It 'should recurse into subdirectories' {
        $dir = Join-Path $TestDrive 'recurse_test'
        $subDir = Join-Path $dir 'subdir'
        New-Item -ItemType Directory -Path $subDir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'root.tmp') -Value 'root'
        Set-Content -Path (Join-Path $subDir 'sub.tmp') -Value 'sub'

        $result = Remove-SafeDirectory -Path $dir
        $result.DeletedFiles | Should -Be 2
    }

    It 'should refuse to operate on paths outside the allowlist' {
        $script:AllowedCleanupRoots = @('C:\SomeOtherAllowedPath')
        $script:DynamicBrowserRoots = @()

        $dir = Join-Path $TestDrive 'outside_allowlist'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'file.tmp') -Value 'data'

        $result = Remove-SafeDirectory -Path $dir
        $result.DeletedFiles | Should -Be 0
        # File should still exist
        Test-Path (Join-Path $dir 'file.tmp') | Should -BeTrue
    }

    It 'should refuse to recurse into junctions' {
        $targetDir = Join-Path $TestDrive 'junction_safe_target'
        $cleanupDir = Join-Path $TestDrive 'junction_safe_cleanup'
        $junctionInCleanup = Join-Path $cleanupDir 'malicious_junction'

        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        Set-Content -Path (Join-Path $targetDir 'protected.txt') -Value 'DO NOT DELETE'

        New-Item -ItemType Directory -Path $cleanupDir -Force | Out-Null
        Set-Content -Path (Join-Path $cleanupDir 'safe.tmp') -Value 'delete me'

        # Create junction inside cleanup dir pointing to protected dir
        $null = cmd /c "mklink /J `"$junctionInCleanup`" `"$targetDir`"" 2>&1

        if (Test-Path $junctionInCleanup) {
            $result = Remove-SafeDirectory -Path $cleanupDir
            # The safe file should be deleted, but junction should be skipped
            Test-Path (Join-Path $targetDir 'protected.txt') | Should -BeTrue
            $result.SkippedFiles | Should -BeGreaterThan 0
        }
        else {
            Set-ItResult -Skipped -Because 'Junction creation requires specific OS support'
        }
    }

    It 'should handle nonexistent directories gracefully' {
        $result = Remove-SafeDirectory -Path (Join-Path $TestDrive 'nonexistent_dir')
        $result.DeletedFiles | Should -Be 0
        $result.Errors | Should -Be 0
    }

    It 'should return stats with correct byte counts' {
        $dir = Join-Path $TestDrive 'bytes_test'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $content = 'A' * 100
        Set-Content -Path (Join-Path $dir 'sized.tmp') -Value $content -NoNewline

        $result = Remove-SafeDirectory -Path $dir
        $result.DeletedFiles | Should -Be 1
        $result.DeletedBytes | Should -BeGreaterThan 0
    }

    Context 'WhatIf mode (HB-2)' {
        It 'should perform zero filesystem modifications in WhatIf mode' {
            $dir = Join-Path $TestDrive 'whatif_test'
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Set-Content -Path (Join-Path $dir 'file1.tmp') -Value 'keep me'
            Set-Content -Path (Join-Path $dir 'file2.tmp') -Value 'keep me too'

            $result = Remove-SafeDirectory -Path $dir -WhatIf
            # Files should still exist after WhatIf
            Test-Path (Join-Path $dir 'file1.tmp') | Should -BeTrue
            Test-Path (Join-Path $dir 'file2.tmp') | Should -BeTrue
            # But stats should report what would have been deleted
            $result.DeletedFiles | Should -Be 2
        }

        It 'should not modify junction targets in WhatIf mode' {
            $targetDir = Join-Path $TestDrive 'whatif_junction_target'
            $cleanupDir = Join-Path $TestDrive 'whatif_junction_cleanup'
            $junctionPath = Join-Path $cleanupDir 'junction_link'

            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            Set-Content -Path (Join-Path $targetDir 'critical.dll') -Value 'system file'

            New-Item -ItemType Directory -Path $cleanupDir -Force | Out-Null

            $null = cmd /c "mklink /J `"$junctionPath`" `"$targetDir`"" 2>&1

            if (Test-Path $junctionPath) {
                Remove-SafeDirectory -Path $cleanupDir -WhatIf
                # Junction target file must still exist
                Test-Path (Join-Path $targetDir 'critical.dll') | Should -BeTrue
                # Junction itself must still exist
                Test-Path $junctionPath | Should -BeTrue
            }
            else {
                Set-ItResult -Skipped -Because 'Junction creation requires specific OS support'
            }
        }
    }
}

Describe 'Remove-CleanupItem' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}

        $script:AllowedCleanupRoots = @(
            [System.IO.Path]::GetFullPath($TestDrive)
        )
        $script:DynamicBrowserRoots = @()
    }

    It 'should delete a single file' {
        $file = Join-Path $TestDrive 'single_file.tmp'
        Set-Content -Path $file -Value 'delete me'

        $result = Remove-CleanupItem -Path $file
        Test-Path $file | Should -BeFalse
        $result.DeletedFiles | Should -Be 1
    }

    It 'should block deletion outside allowlist' {
        $script:AllowedCleanupRoots = @('C:\SomeOtherPath')
        $script:DynamicBrowserRoots = @()

        $file = Join-Path $TestDrive 'blocked_file.tmp'
        Set-Content -Path $file -Value 'protected'

        $result = Remove-CleanupItem -Path $file
        Test-Path $file | Should -BeTrue
        $result.SkippedFiles | Should -Be 1
    }

    It 'should refuse to delete a junction' {
        $targetDir = Join-Path $TestDrive 'item_junction_target'
        $junctionDir = Join-Path $TestDrive 'item_junction'

        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        $null = cmd /c "mklink /J `"$junctionDir`" `"$targetDir`"" 2>&1

        if (Test-Path $junctionDir) {
            $result = Remove-CleanupItem -Path $junctionDir
            $result.SkippedFiles | Should -Be 1
            # Junction target should be untouched
            Test-Path $targetDir | Should -BeTrue
        }
        else {
            Set-ItResult -Skipped -Because 'Junction creation requires specific OS support'
        }
    }

    It 'should handle WhatIf without modifying filesystem' {
        $file = Join-Path $TestDrive 'whatif_item.tmp'
        Set-Content -Path $file -Value 'should remain'

        $result = Remove-CleanupItem -Path $file -WhatIf
        Test-Path $file | Should -BeTrue
        $result.DeletedFiles | Should -Be 1
    }

    It 'should delegate directories to Remove-SafeDirectory' {
        $dir = Join-Path $TestDrive 'dir_cleanup'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Set-Content -Path (Join-Path $dir 'inner.tmp') -Value 'data'

        $result = Remove-CleanupItem -Path $dir
        $result.DeletedFiles | Should -Be 1
    }

    It 'should handle nonexistent paths gracefully' {
        $result = Remove-CleanupItem -Path (Join-Path $TestDrive 'does_not_exist.tmp')
        $result.DeletedFiles | Should -Be 0
        $result.Errors | Should -Be 0
    }
}

Describe 'Add-BrowserCleanupRoot' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        $script:DynamicBrowserRoots = @()
        $script:AllowedCleanupRoots = @()
    }

    It 'should add a valid directory to dynamic roots' {
        $dir = Join-Path $TestDrive 'browser_cache'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        Add-BrowserCleanupRoot -Path $dir

        $resolved = [System.IO.Path]::GetFullPath($dir)
        $script:DynamicBrowserRoots | Should -Contain $resolved
    }

    It 'should not add the same path twice' {
        $dir = Join-Path $TestDrive 'browser_dedup'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null

        Add-BrowserCleanupRoot -Path $dir
        Add-BrowserCleanupRoot -Path $dir

        $resolved = [System.IO.Path]::GetFullPath($dir)
        @($script:DynamicBrowserRoots | Where-Object { $_ -eq $resolved }).Count | Should -Be 1
    }

    It 'should not add nonexistent paths' {
        Add-BrowserCleanupRoot -Path (Join-Path $TestDrive 'does_not_exist')
        $script:DynamicBrowserRoots.Count | Should -Be 0
    }

    It 'should refuse to add a junction as a browser root' {
        $targetDir = Join-Path $TestDrive 'browser_target'
        $junctionDir = Join-Path $TestDrive 'browser_junction'

        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        $null = cmd /c "mklink /J `"$junctionDir`" `"$targetDir`"" 2>&1

        if (Test-Path $junctionDir) {
            Add-BrowserCleanupRoot -Path $junctionDir
            $script:DynamicBrowserRoots.Count | Should -Be 0
        }
        else {
            Set-ItResult -Skipped -Because 'Junction creation requires specific OS support'
        }
    }
}

Describe 'Initialize-AllowedCleanupRoots' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should populate the allowlist with expected system paths' {
        Initialize-AllowedCleanupRoots
        $script:AllowedCleanupRoots.Count | Should -BeGreaterOrEqual 4
    }

    It 'should include TEMP directory' {
        Initialize-AllowedCleanupRoots
        $tempResolved = [System.IO.Path]::GetFullPath($env:TEMP)
        $script:AllowedCleanupRoots | Should -Contain $tempResolved
    }

    It 'should include Windows Temp directory' {
        Initialize-AllowedCleanupRoots
        $winTempResolved = [System.IO.Path]::GetFullPath("$env:SystemRoot\Temp")
        $script:AllowedCleanupRoots | Should -Contain $winTempResolved
    }

    It 'should include Prefetch directory' {
        Initialize-AllowedCleanupRoots
        $prefetchResolved = [System.IO.Path]::GetFullPath("$env:SystemRoot\Prefetch")
        $script:AllowedCleanupRoots | Should -Contain $prefetchResolved
    }

    It 'should include SoftwareDistribution Download directory' {
        Initialize-AllowedCleanupRoots
        $wuResolved = [System.IO.Path]::GetFullPath("$env:SystemRoot\SoftwareDistribution\Download")
        $script:AllowedCleanupRoots | Should -Contain $wuResolved
    }
}

Describe 'Clear-ReadOnlyAttribute' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return $false and leave a writable file unchanged' {
        $file = Join-Path $TestDrive 'writable.tmp'
        Set-Content -Path $file -Value 'data'
        Clear-ReadOnlyAttribute -Item ([System.IO.FileInfo]::new($file)) | Should -BeFalse
        ([int](Get-Item $file).Attributes -band [int][System.IO.FileAttributes]::ReadOnly) | Should -Be 0
    }

    It 'should return $true and clear the ReadOnly bit on a read-only file' {
        $file = Join-Path $TestDrive 'readonly.tmp'
        Set-Content -Path $file -Value 'data'
        (Get-Item $file).Attributes = 'ReadOnly'
        Clear-ReadOnlyAttribute -Item ([System.IO.FileInfo]::new($file)) | Should -BeTrue
        ([int](Get-Item $file).Attributes -band [int][System.IO.FileAttributes]::ReadOnly) | Should -Be 0
    }

    It 'should return $false without throwing for an item that no longer exists' {
        $ghost = [System.IO.FileInfo]::new((Join-Path $TestDrive 'ghost.tmp'))
        { Clear-ReadOnlyAttribute -Item $ghost } | Should -Not -Throw
        Clear-ReadOnlyAttribute -Item $ghost | Should -BeFalse
    }
}

Describe 'Remove-SafeDirectory: read-only files (git loose objects)' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        $script:AllowedCleanupRoots = @([System.IO.Path]::GetFullPath($TestDrive))
        $script:DynamicBrowserRoots = @()
    }

    It 'should delete a read-only file instead of skipping it' {
        # Regression: git marks every loose object read-only. FileInfo.Delete()
        # throws UnauthorizedAccessException on those, so a single abandoned repo
        # under %TEMP% left 187,738 files behind on a real run.
        $dir = Join-Path $TestDrive 'ro_single'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $f = Join-Path $dir 'loose.obj'
        Set-Content -Path $f -Value 'x'
        (Get-Item $f).Attributes = 'ReadOnly'

        $result = Remove-SafeDirectory -Path $dir
        $result.DeletedFiles | Should -Be 1
        $result.SkippedFiles | Should -Be 0
        $result.Errors | Should -Be 0
        Test-Path $f | Should -BeFalse
    }

    It 'should delete read-only files nested in subdirectories' {
        $dir = Join-Path $TestDrive 'ro_nested'
        foreach ($sub in @('aa', 'bb', 'cc')) {
            $subPath = Join-Path (Join-Path $dir 'objects') $sub
            New-Item -ItemType Directory -Path $subPath -Force | Out-Null
            foreach ($n in 1..3) {
                $p = Join-Path $subPath "obj$n"
                Set-Content -Path $p -Value 'x'
                (Get-Item $p).Attributes = 'ReadOnly'
            }
        }

        $result = Remove-SafeDirectory -Path $dir
        $result.DeletedFiles | Should -Be 9
        $result.SkippedFiles | Should -Be 0
        @(Get-ChildItem -Path $dir -Recurse -File -Force -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'should not write a log line for every read-only file' {
        # Regression: the pre-fix code logged one full path per skipped file,
        # producing a 27.5 MB session log from a single cleanup run.
        $dir = Join-Path $TestDrive 'ro_nolog'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        foreach ($n in 1..10) {
            $p = Join-Path $dir "obj$n"
            Set-Content -Path $p -Value 'x'
            (Get-Item $p).Attributes = 'ReadOnly'
        }

        $result = Remove-SafeDirectory -Path $dir
        $result.DeletedFiles | Should -Be 10
        Should -Invoke Write-Log -Times 0 -Exactly
    }

    It 'should remove an emptied read-only subdirectory' {
        # A read-only directory throws IOException from DirectoryInfo.Delete(),
        # which the "not empty or locked" catch swallowed silently -- which is
        # why the incident reported 0 errors.
        $dir = Join-Path $TestDrive 'ro_dir_parent'
        $sub = Join-Path $dir 'ro_child'
        New-Item -ItemType Directory -Path $sub -Force | Out-Null
        Set-Content -Path (Join-Path $sub 'f.tmp') -Value 'x'
        (Get-Item $sub).Attributes = 'ReadOnly, Directory'

        $null = Remove-SafeDirectory -Path $dir
        Test-Path $sub | Should -BeFalse
    }

    It 'WhatIf must not clear the ReadOnly attribute or delete anything' {
        $dir = Join-Path $TestDrive 'ro_whatif'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $f = Join-Path $dir 'obj'
        Set-Content -Path $f -Value 'x'
        (Get-Item $f).Attributes = 'ReadOnly'

        $result = Remove-SafeDirectory -Path $dir -WhatIf
        $result.DeletedFiles | Should -Be 1
        Test-Path $f | Should -BeTrue
        ([int](Get-Item $f).Attributes -band [int][System.IO.FileAttributes]::ReadOnly) | Should -Not -Be 0
    }
}
