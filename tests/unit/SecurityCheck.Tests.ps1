# ==============================================================================
# PC Cleanup v2 -- SecurityCheck Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
    . "$PSScriptRoot/../../src/modules/SecurityCheck.ps1"
}

Describe 'Get-DefenderStatus' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return an object with expected properties' {
        Mock -CommandName Get-MpComputerStatus -MockWith {
            [PSCustomObject]@{
                AntivirusEnabled = $true
                RealTimeProtectionEnabled = $true
                AMEngineVersion = '1.1.24010.10'
                AntivirusSignatureLastUpdated = (Get-Date).AddDays(-1)
            }
        }
        $result = Get-DefenderStatus
        $result.Available | Should -BeTrue
        $result.RealTimeProtection | Should -BeTrue
        $result.EngineVersion | Should -Not -BeNullOrEmpty
        $result.SignatureAge | Should -BeLessOrEqual 2
    }

    It 'should handle Get-MpComputerStatus failure gracefully' {
        Mock -CommandName Get-MpComputerStatus -MockWith { throw 'Not available' }
        $result = Get-DefenderStatus
        $result.Message | Should -Not -BeNullOrEmpty
    }

    It 'should calculate signature age correctly' {
        Mock -CommandName Get-MpComputerStatus -MockWith {
            [PSCustomObject]@{
                AntivirusEnabled = $true
                RealTimeProtectionEnabled = $true
                AMEngineVersion = '1.0'
                AntivirusSignatureLastUpdated = (Get-Date).AddDays(-5)
            }
        }
        $result = Get-DefenderStatus
        $result.SignatureAge | Should -BeGreaterOrEqual 4
        $result.SignatureAge | Should -BeLessOrEqual 6
    }

    It 'should report real-time protection as disabled when off' {
        Mock -CommandName Get-MpComputerStatus -MockWith {
            [PSCustomObject]@{
                AntivirusEnabled = $true
                RealTimeProtectionEnabled = $false
                AMEngineVersion = '1.0'
                AntivirusSignatureLastUpdated = (Get-Date)
            }
        }
        $result = Get-DefenderStatus
        $result.RealTimeProtection | Should -BeFalse
    }
}

Describe 'Get-FirewallStatus' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return profiles with expected properties' {
        Mock -CommandName Get-NetFirewallProfile -MockWith {
            @(
                [PSCustomObject]@{ Name = 'Domain'; Enabled = $true }
                [PSCustomObject]@{ Name = 'Private'; Enabled = $true }
                [PSCustomObject]@{ Name = 'Public'; Enabled = $false }
            )
        }
        $result = Get-FirewallStatus
        $result.Count | Should -Be 3
        ($result | Where-Object { $_.Profile -eq 'Domain' }).Enabled | Should -BeTrue
        ($result | Where-Object { $_.Profile -eq 'Public' }).Enabled | Should -BeFalse
    }

    It 'should handle Get-NetFirewallProfile failure gracefully' {
        Mock -CommandName Get-NetFirewallProfile -MockWith { throw 'Not available' }
        # Should fall back to netsh -- may or may not work in test env but should not throw
        { Get-FirewallStatus } | Should -Not -Throw
    }
}

Describe 'Test-SMBv1Enabled' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should detect SMBv1 as enabled via WindowsOptionalFeature' {
        Mock -CommandName Get-WindowsOptionalFeature -MockWith {
            [PSCustomObject]@{ State = 'Enabled' }
        }
        $result = Test-SMBv1Enabled
        $result.Enabled | Should -BeTrue
        $result.Source | Should -Be 'WindowsOptionalFeature'
    }

    It 'should detect SMBv1 as disabled via WindowsOptionalFeature' {
        Mock -CommandName Get-WindowsOptionalFeature -MockWith {
            [PSCustomObject]@{ State = 'Disabled' }
        }
        $result = Test-SMBv1Enabled
        $result.Enabled | Should -BeFalse
    }

    It 'should fall back to registry when WindowsOptionalFeature fails' {
        Mock -CommandName Get-WindowsOptionalFeature -MockWith { throw 'Not admin' }
        Mock -CommandName Get-ItemProperty -MockWith {
            [PSCustomObject]@{ SMB1 = 0 }
        }
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        $result = Test-SMBv1Enabled
        $result.Enabled | Should -BeFalse
    }

    It 'should return an object with expected properties' {
        Mock -CommandName Get-WindowsOptionalFeature -MockWith {
            [PSCustomObject]@{ State = 'Disabled' }
        }
        $result = Test-SMBv1Enabled
        $result.PSObject.Properties.Name | Should -Contain 'Enabled'
        $result.PSObject.Properties.Name | Should -Contain 'Source'
        $result.PSObject.Properties.Name | Should -Contain 'Message'
    }
}

Describe 'Get-PendingUpdates' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should handle COM object failure gracefully' {
        Mock -CommandName New-Object -MockWith { throw 'COM not available' } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
        $result = Get-PendingUpdates
        $result.Count | Should -Be -1
        $result.Message | Should -Not -BeNullOrEmpty
    }

    It 'should return an object with expected properties' {
        Mock -CommandName New-Object -MockWith { throw 'COM not available' } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
        $result = Get-PendingUpdates
        $result.PSObject.Properties.Name | Should -Contain 'Count'
        $result.PSObject.Properties.Name | Should -Contain 'Updates'
        $result.PSObject.Properties.Name | Should -Contain 'Message'
    }
}

Describe 'Get-SecurityReport' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-MpComputerStatus -MockWith {
            [PSCustomObject]@{
                AntivirusEnabled = $true
                RealTimeProtectionEnabled = $true
                AMEngineVersion = '1.1.24010.10'
                AntivirusSignatureLastUpdated = (Get-Date)
            }
        }
        Mock -CommandName Get-NetFirewallProfile -MockWith {
            @(
                [PSCustomObject]@{ Name = 'Domain'; Enabled = $true }
                [PSCustomObject]@{ Name = 'Private'; Enabled = $true }
                [PSCustomObject]@{ Name = 'Public'; Enabled = $true }
            )
        }
        Mock -CommandName Get-WindowsOptionalFeature -MockWith {
            [PSCustomObject]@{ State = 'Disabled' }
        }
        Mock -CommandName New-Object -MockWith { throw 'COM not available' } -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' }
    }

    It 'should return aggregate report with all checks' {
        $result = Get-SecurityReport
        $result.PSObject.Properties.Name | Should -Contain 'Defender'
        $result.PSObject.Properties.Name | Should -Contain 'Firewall'
        $result.PSObject.Properties.Name | Should -Contain 'SMBv1'
        $result.PSObject.Properties.Name | Should -Contain 'Updates'
        $result.PSObject.Properties.Name | Should -Contain 'Grade'
    }

    It 'should assign grade A when no issues found' {
        $result = Get-SecurityReport
        $result.Issues | Should -Be 0
        $result.Grade | Should -Be 'A'
    }

    It 'should increase issue count for disabled real-time protection' {
        Mock -CommandName Get-MpComputerStatus -MockWith {
            [PSCustomObject]@{
                AntivirusEnabled = $false
                RealTimeProtectionEnabled = $false
                AMEngineVersion = '1.0'
                AntivirusSignatureLastUpdated = (Get-Date)
            }
        }
        $result = Get-SecurityReport
        $result.Issues | Should -BeGreaterThan 0
    }

    It 'should increase issue count for disabled firewall profile' {
        Mock -CommandName Get-NetFirewallProfile -MockWith {
            @(
                [PSCustomObject]@{ Name = 'Domain'; Enabled = $false }
                [PSCustomObject]@{ Name = 'Private'; Enabled = $true }
                [PSCustomObject]@{ Name = 'Public'; Enabled = $true }
            )
        }
        $result = Get-SecurityReport
        $result.Issues | Should -BeGreaterThan 0
    }

    It 'should increase issue count for enabled SMBv1' {
        Mock -CommandName Get-WindowsOptionalFeature -MockWith {
            [PSCustomObject]@{ State = 'Enabled' }
        }
        $result = Get-SecurityReport
        $result.Issues | Should -BeGreaterThan 0
    }

    It 'should display report header' {
        Get-SecurityReport
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*SECURITY HEALTH CHECK*' }
    }

    It 'should display overall grade' {
        Get-SecurityReport
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Overall Security Grade*' }
    }
}
