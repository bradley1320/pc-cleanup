# ==============================================================================
# PC Cleanup v2 -- SystemReport Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
    . "$PSScriptRoot/../../src/modules/SystemReport.ps1"
}

Describe 'Get-BootTimeMeasurement' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return Event ID 100 data when available' {
        Mock -CommandName Get-WinEvent -MockWith {
            $event = [PSCustomObject]@{
                Properties = @(
                    [PSCustomObject]@{ Value = 15000 }
                    [PSCustomObject]@{ Value = 5000 }
                )
            }
            return $event
        }
        $result = Get-BootTimeMeasurement
        $result.BootTimeMs | Should -Be 20000
        $result.Source | Should -Be 'EventID100'
    }

    It 'should fall back to CIM when Event ID 100 unavailable' {
        Mock -CommandName Get-WinEvent -MockWith { throw 'Log not found' }
        Mock -CommandName Get-CimInstance -MockWith {
            [PSCustomObject]@{ LastBootUpTime = (Get-Date).AddMinutes(-30) }
        }
        $result = Get-BootTimeMeasurement
        $result.Source | Should -Be 'CIM'
        $result.BootTimeMs | Should -BeGreaterThan 0
    }

    It 'should return Unavailable when both sources fail' {
        Mock -CommandName Get-WinEvent -MockWith { throw 'Log not found' }
        Mock -CommandName Get-CimInstance -MockWith { throw 'CIM error' }
        $result = Get-BootTimeMeasurement
        $result.Source | Should -Be 'Unavailable'
        $result.BootTimeMs | Should -Be -1
    }
}

Describe 'Get-SystemSnapshot' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-WinEvent -MockWith {
            [PSCustomObject]@{
                Properties = @(
                    [PSCustomObject]@{ Value = 10000 }
                    [PSCustomObject]@{ Value = 3000 }
                )
            }
        }
    }

    It 'should return snapshot with all required properties' {
        $result = Get-SystemSnapshot
        $result.PSObject.Properties.Name | Should -Contain 'BootTimeMs'
        $result.PSObject.Properties.Name | Should -Contain 'BootTimeSource'
        $result.PSObject.Properties.Name | Should -Contain 'ProcessCount'
        $result.PSObject.Properties.Name | Should -Contain 'FreeDiskBytes'
        $result.PSObject.Properties.Name | Should -Contain 'StartupCount'
        $result.PSObject.Properties.Name | Should -Contain 'CapturedAt'
    }

    It 'should capture positive process count' {
        $result = Get-SystemSnapshot
        $result.ProcessCount | Should -BeGreaterThan 0
    }

    It 'should capture positive free disk space' {
        $result = Get-SystemSnapshot
        $result.FreeDiskBytes | Should -BeGreaterThan 0
    }

    It 'should capture ISO 8601 timestamp' {
        $result = Get-SystemSnapshot
        # ISO 8601 format contains a T separator
        $result.CapturedAt | Should -Match 'T'
    }
}

Describe 'Save-SystemSnapshot' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-WinEvent -MockWith {
            [PSCustomObject]@{
                Properties = @(
                    [PSCustomObject]@{ Value = 10000 }
                    [PSCustomObject]@{ Value = 3000 }
                )
            }
        }
        $script:SnapshotDir = Join-Path $TestDrive "snapshots_$(Get-Random)"
    }

    It 'should save snapshot file to disk' {
        Save-SystemSnapshot -Label 'Before'
        $files = Get-ChildItem -Path $script:SnapshotDir -Filter 'snapshot_Before_*.json' -File
        $files.Count | Should -Be 1
    }

    It 'should save valid JSON' {
        Save-SystemSnapshot -Label 'TestLabel'
        $files = Get-ChildItem -Path $script:SnapshotDir -Filter 'snapshot_TestLabel_*.json' -File
        $content = Get-Content -Path $files[0].FullName -Raw
        { $content | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'should sanitize label for filename safety' {
        Save-SystemSnapshot -Label 'Before/After!'
        $files = Get-ChildItem -Path $script:SnapshotDir -Filter 'snapshot_Before_After_*.json' -File
        $files.Count | Should -Be 1
    }

    It 'should return snapshot object' {
        $result = Save-SystemSnapshot -Label 'Test'
        $result.BootTimeMs | Should -Not -BeNullOrEmpty
        $result.ProcessCount | Should -BeGreaterThan 0
    }

    It 'should create snapshot directory if it does not exist' {
        Test-Path $script:SnapshotDir | Should -BeFalse
        Save-SystemSnapshot -Label 'New'
        Test-Path $script:SnapshotDir | Should -BeTrue
    }
}

Describe 'Compare-Snapshots' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        $script:SnapshotDir = Join-Path $TestDrive "snapshots_$(Get-Random)"
        New-Item -ItemType Directory -Path $script:SnapshotDir -Force | Out-Null
    }

    It 'should warn when no snapshots exist' {
        $script:SnapshotDir = Join-Path $TestDrive "nonexistent_$(Get-Random)"
        Compare-Snapshots
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No snapshots found*' }
    }

    It 'should warn when only one snapshot exists' {
        $snapshot = @{ BootTimeMs = 10000; BootTimeSource = 'EventID100'; ProcessCount = 100; FreeDiskBytes = 50000000000; StartupCount = 10; CapturedAt = (Get-Date).ToString('o') }
        $snapshot | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_Before_20260224_100000.json')
        Compare-Snapshots
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Need at least 2*' }
    }

    It 'should display comparison when before and after snapshots exist' {
        $before = @{ BootTimeMs = 20000; BootTimeSource = 'EventID100'; ProcessCount = 150; FreeDiskBytes = 50000000000; StartupCount = 15; CapturedAt = (Get-Date).AddHours(-2).ToString('o') }
        $after = @{ BootTimeMs = 15000; BootTimeSource = 'EventID100'; ProcessCount = 120; FreeDiskBytes = 55000000000; StartupCount = 10; CapturedAt = (Get-Date).ToString('o') }
        $before | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_Before_20260224_100000.json')
        $after | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_After_20260224_120000.json')
        $result = Compare-Snapshots
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*SYSTEM METRICS COMPARISON*' }
        $result.Before | Should -Not -BeNullOrEmpty
        $result.After | Should -Not -BeNullOrEmpty
    }

    It 'should note when boot time sources differ' {
        $before = @{ BootTimeMs = 20000; BootTimeSource = 'EventID100'; ProcessCount = 150; FreeDiskBytes = 50000000000; StartupCount = 15; CapturedAt = (Get-Date).AddHours(-2).ToString('o') }
        $after = @{ BootTimeMs = 15000; BootTimeSource = 'CIM'; ProcessCount = 120; FreeDiskBytes = 55000000000; StartupCount = 10; CapturedAt = (Get-Date).ToString('o') }
        $before | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_Before_20260224_100000.json')
        $after | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_After_20260224_120000.json')
        Compare-Snapshots
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*sources differ*' }
    }

    It 'should warn about CIM being less granular when privacy tweaks disable logging' {
        $before = @{ BootTimeMs = 20000; BootTimeSource = 'EventID100'; ProcessCount = 150; FreeDiskBytes = 50000000000; StartupCount = 15; CapturedAt = (Get-Date).AddHours(-2).ToString('o') }
        $after = @{ BootTimeMs = 15000; BootTimeSource = 'CIM'; ProcessCount = 120; FreeDiskBytes = 55000000000; StartupCount = 10; CapturedAt = (Get-Date).ToString('o') }
        $before | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_Before_20260224_100000.json')
        $after | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_After_20260224_120000.json')
        Compare-Snapshots
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*diagnostic logging may be disabled*' }
    }
}

Describe 'Show-MetricDelta' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should display improvement in green when lower is better and value decreased' {
        Show-MetricDelta -Label 'Boot Time' -Before 20000 -After 15000 -Unit 'ms' -LowerIsBetter $true
        Should -Invoke Write-Host -ParameterFilter { $ForegroundColor -eq 'Green' }
    }

    It 'should display regression in red when lower is better and value increased' {
        Show-MetricDelta -Label 'Boot Time' -Before 15000 -After 20000 -Unit 'ms' -LowerIsBetter $true
        Should -Invoke Write-Host -ParameterFilter { $ForegroundColor -eq 'Red' }
    }

    It 'should display improvement in green when higher is better and value increased' {
        Show-MetricDelta -Label 'Free Space' -Before 50000 -After 55000 -Unit 'MB' -LowerIsBetter $false
        Should -Invoke Write-Host -ParameterFilter { $ForegroundColor -eq 'Green' }
    }

    It 'should display no change in gray' {
        Show-MetricDelta -Label 'Count' -Before 100 -After 100 -Unit '' -LowerIsBetter $true
        Should -Invoke Write-Host -ParameterFilter { $ForegroundColor -eq 'DarkGray' }
    }
}
