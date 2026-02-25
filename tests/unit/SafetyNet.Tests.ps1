# ==============================================================================
# PC Cleanup v2 — SafetyNet Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
    . "$PSScriptRoot/../../src/core/03-SafetyNet.ps1"
}

Describe 'New-SafetyRestorePoint' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return false when not running as admin' {
        Mock -CommandName Test-IsAdmin -MockWith { $false }
        New-SafetyRestorePoint | Should -BeFalse
    }

    It 'should return false when System Restore is disabled' {
        Mock -CommandName Test-IsAdmin -MockWith { $true }
        Mock -CommandName Get-ItemProperty -MockWith {
            [PSCustomObject]@{ RPSessionInterval = 0 }
        }
        New-SafetyRestorePoint | Should -BeFalse
    }

    It 'should skip duplicate when recent PCCleanup restore point exists' {
        Mock -CommandName Test-IsAdmin -MockWith { $true }
        Mock -CommandName Get-ItemProperty -MockWith {
            [PSCustomObject]@{ RPSessionInterval = 1 }
        }
        # Return a recent PCCleanup restore point
        $recentTime = [System.Management.ManagementDateTimeConverter]::ToDmtfDateTime((Get-Date).AddHours(-1))
        Mock -CommandName Get-ComputerRestorePoint -MockWith {
            @([PSCustomObject]@{
                Description  = 'PCCleanup Safety Point'
                CreationTime = $recentTime
            })
        }
        New-SafetyRestorePoint | Should -BeTrue
    }

    It 'should return false on timeout' {
        Mock -CommandName Test-IsAdmin -MockWith { $true }
        Mock -CommandName Get-ItemProperty -MockWith {
            [PSCustomObject]@{ RPSessionInterval = 1 }
        }
        Mock -CommandName Get-ComputerRestorePoint -MockWith { @() }
        Mock -CommandName Start-Job -MockWith {
            [PSCustomObject]@{ State = 'Running'; ChildJobs = @([PSCustomObject]@{ Error = @() }) }
        }
        Mock -CommandName Wait-Job -MockWith { $null }
        Mock -CommandName Stop-Job -MockWith {}
        Mock -CommandName Remove-Job -MockWith {}
        New-SafetyRestorePoint | Should -BeFalse
    }
}

Describe 'Backup-RegistryHive' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should create output directory if missing' {
        $outputDir = Join-Path $TestDrive 'backups'
        Mock -CommandName reg.exe -MockWith { }
        # Mock Test-Path to return true for the output file
        Mock -CommandName Test-Path -MockWith { $true } -ParameterFilter { $Path -like '*PCCleanup_*' }
        Backup-RegistryHive -Path 'HKLM:\SOFTWARE' -OutputDir $outputDir
        Test-Path $outputDir | Should -BeTrue
    }

    It 'should return null on failure' {
        $outputDir = Join-Path $TestDrive 'backups_fail'
        Mock -CommandName reg.exe -MockWith { throw 'Export failed' }
        $result = Backup-RegistryHive -Path 'HKLM:\NONEXISTENT' -OutputDir $outputDir
        $result | Should -BeNullOrEmpty
    }
}

Describe 'Get-SafetyStatus' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return a PSCustomObject with expected properties' {
        Mock -CommandName Get-ComputerRestorePoint -MockWith { @() }
        $result = Get-SafetyStatus
        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'RestorePoints'
        $result.PSObject.Properties.Name | Should -Contain 'Backups'
        $result.PSObject.Properties.Name | Should -Contain 'UndoLogEntries'
    }

    It 'should return zero counts when nothing exists' {
        Mock -CommandName Get-ComputerRestorePoint -MockWith { @() }
        $result = Get-SafetyStatus
        $result.RestorePoints | Should -Be 0
        $result.Backups | Should -Be 0
        $result.UndoLogEntries | Should -Be 0
    }

    It 'should count backup files in the backup directory' {
        Mock -CommandName Get-ComputerRestorePoint -MockWith { @() }
        # Create actual .reg files in the real backup dir
        $backupDir = Join-Path $env:LOCALAPPDATA 'PCCleanup\backups'
        if (-not (Test-Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }
        $f1 = Join-Path $backupDir 'test_backup1.reg'
        $f2 = Join-Path $backupDir 'test_backup2.reg'
        'test' | Set-Content -Path $f1
        'test' | Set-Content -Path $f2
        try {
            $result = Get-SafetyStatus
            $result.Backups | Should -BeGreaterOrEqual 2
        }
        finally {
            Remove-Item -Path $f1 -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $f2 -Force -ErrorAction SilentlyContinue
        }
    }
}
