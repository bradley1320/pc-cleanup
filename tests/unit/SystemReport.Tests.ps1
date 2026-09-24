# ==============================================================================
# PC Cleanup v2 -- SystemReport Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
    . "$PSScriptRoot/../../src/modules/SystemReport.ps1"

    # Stand-in for a real Event ID 100 record, in Windows' own field order. The
    # event has 40+ fields and the first three are a version number and two
    # timestamps, so code that reads Properties by position fails against it --
    # which is how v2.0.0 came to report uptime as boot time.
    function New-BootEvent {
        param([long]$MainPathMs, [long]$PostBootMs)

        $start = [datetime]'2026-09-22T19:23:38'
        $fields = [ordered]@{
            BootTsVersion      = [uint32]2
            BootStartTime      = $start
            BootEndTime        = $start.AddMilliseconds($MainPathMs + $PostBootMs)
            SystemBootInstance = [uint32]155
            UserBootInstance   = [uint32]154
            BootTime           = [uint32]($MainPathMs + $PostBootMs)
            MainPathBootTime   = [uint32]$MainPathMs
            BootKernelInitTime = [uint32]74
            BootPostBootTime   = [uint32]$PostBootMs
        }
        $data = foreach ($name in $fields.Keys) {
            $value = $fields[$name]
            if ($value -is [datetime]) { $value = $value.ToString('o') }
            "<Data Name='$name'>$value</Data>"
        }
        $xml = "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'>" +
            "<System><EventID>100</EventID></System><EventData>$($data -join '')</EventData></Event>"

        $bootEvent = [PSCustomObject]@{
            Properties = @($fields.Values | ForEach-Object { [PSCustomObject]@{ Value = $_ } })
        }
        $bootEvent | Add-Member -MemberType ScriptMethod -Name ToXml -Value { $xml }.GetNewClosure()
        $bootEvent
    }
}

Describe 'Get-BootTimeMeasurement' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should read MainPathBootTime and BootPostBootTime by name from a real-layout event' {
        Mock -CommandName Get-WinEvent -MockWith { New-BootEvent -MainPathMs 36019 -PostBootMs 40900 }
        $result = Get-BootTimeMeasurement
        $result.BootTimeMs | Should -Be 76919
        $result.Source | Should -Be 'EventID100'
    }

    It 'should report Unavailable, not uptime, when Event ID 100 cannot be read' {
        Mock -CommandName Get-WinEvent -MockWith { throw 'No events were found that match the specified selection criteria.' }
        Mock -CommandName Get-CimInstance -MockWith {
            [PSCustomObject]@{ LastBootUpTime = (Get-Date).AddHours(-8) }
        }
        $result = Get-BootTimeMeasurement
        $result.Source | Should -Be 'Unavailable'
        $result.BootTimeMs | Should -Be -1
        Should -Invoke Get-CimInstance -Times 0 -Exactly
    }

    It 'should report Unavailable when the event lacks the timing fields' {
        Mock -CommandName Get-WinEvent -MockWith {
            $bootEvent = [PSCustomObject]@{}
            $bootEvent | Add-Member -MemberType ScriptMethod -Name ToXml -Value {
                "<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><EventData><Data Name='BootTsVersion'>2</Data></EventData></Event>"
            }
            $bootEvent
        }
        $result = Get-BootTimeMeasurement
        $result.Source | Should -Be 'Unavailable'
        $result.BootTimeMs | Should -Be -1
    }
}

Describe 'Format-BootTime' {
    It 'should show a measured boot time with its source' {
        Format-BootTime -BootTimeMs 76919 -Source 'EventID100' | Should -Be '76919ms (source: Event ID 100)'
    }

    It 'should say that a v2.0.0 CIM snapshot held uptime, not boot time' {
        Format-BootTime -BootTimeMs 30682830 -Source 'CIM' | Should -BeLike '*uptime*'
    }

    It 'should say not available instead of printing the -1 sentinel' {
        $text = Format-BootTime -BootTimeMs -1 -Source 'Unavailable'
        $text | Should -BeLike 'not available*'
        $text | Should -Not -BeLike '*-1*'
    }
}

Describe 'Get-SystemSnapshot' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-WinEvent -MockWith { New-BootEvent -MainPathMs 10000 -PostBootMs 3000 }
    }

    It 'should record boot time from Event ID 100' {
        $result = Get-SystemSnapshot
        $result.BootTimeMs | Should -Be 13000
        $result.BootTimeSource | Should -Be 'EventID100'
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
        Mock -CommandName Get-WinEvent -MockWith { New-BootEvent -MainPathMs 10000 -PostBootMs 3000 }
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
        Mock -CommandName Show-MetricDelta -MockWith {}
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

    It 'should compare boot time when both snapshots measured it' {
        $before = @{ BootTimeMs = 20000; BootTimeSource = 'EventID100'; ProcessCount = 150; FreeDiskBytes = 50000000000; StartupCount = 15; CapturedAt = (Get-Date).AddHours(-2).ToString('o') }
        $after = @{ BootTimeMs = 15000; BootTimeSource = 'EventID100'; ProcessCount = 120; FreeDiskBytes = 55000000000; StartupCount = 10; CapturedAt = (Get-Date).ToString('o') }
        $before | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_Before_20260224_100000.json')
        $after | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_After_20260224_120000.json')
        Compare-Snapshots
        Should -Invoke Show-MetricDelta -Times 1 -Exactly -ParameterFilter { $Label -eq 'Boot Time' -and $Before -eq 20000 -and $After -eq 15000 }
    }

    It 'should not compare boot time when a snapshot did not measure it' {
        $before = @{ BootTimeMs = 20000; BootTimeSource = 'EventID100'; ProcessCount = 150; FreeDiskBytes = 50000000000; StartupCount = 15; CapturedAt = (Get-Date).AddHours(-2).ToString('o') }
        $after = @{ BootTimeMs = -1; BootTimeSource = 'Unavailable'; ProcessCount = 120; FreeDiskBytes = 55000000000; StartupCount = 10; CapturedAt = (Get-Date).ToString('o') }
        $before | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_Before_20260224_100000.json')
        $after | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_After_20260224_120000.json')
        Compare-Snapshots
        Should -Invoke Show-MetricDelta -Times 0 -Exactly -ParameterFilter { $Label -eq 'Boot Time' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*not compared*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*not available*' }
    }

    It 'should not compare boot time against a v2.0.0 snapshot that recorded uptime' {
        # v2.0.0 saved uptime under the CIM source: hours before a reboot,
        # minutes after, so a delta would show a speed-up that never happened.
        $before = @{ BootTimeMs = 30682830; BootTimeSource = 'CIM'; ProcessCount = 150; FreeDiskBytes = 50000000000; StartupCount = 15; CapturedAt = (Get-Date).AddHours(-2).ToString('o') }
        $after = @{ BootTimeMs = 76919; BootTimeSource = 'EventID100'; ProcessCount = 120; FreeDiskBytes = 55000000000; StartupCount = 10; CapturedAt = (Get-Date).ToString('o') }
        $before | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_Before_20260224_100000.json')
        $after | ConvertTo-Json | Set-Content (Join-Path $script:SnapshotDir 'snapshot_After_20260224_120000.json')
        Compare-Snapshots
        Should -Invoke Show-MetricDelta -Times 0 -Exactly -ParameterFilter { $Label -eq 'Boot Time' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*uptime*' }
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
