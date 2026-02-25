# ==============================================================================
# PC Cleanup v2 — SystemInfo Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
}

Describe 'Get-OSBuild' {
    It 'should return an integer' {
        Mock -CommandName Write-Log -MockWith {}
        $result = Get-OSBuild
        $result | Should -BeOfType [int]
    }

    It 'should return a value greater than zero on Windows' {
        Mock -CommandName Write-Log -MockWith {}
        $result = Get-OSBuild
        $result | Should -BeGreaterThan 0
    }

    It 'should return 0 on error' {
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Get-ItemProperty -MockWith { throw 'Registry error' }
        $result = Get-OSBuild
        $result | Should -Be 0
    }
}

Describe 'Test-IsSSD' {
    It 'should return a boolean' {
        # Use the real system — just check the return type
        $result = Test-IsSSD -DriveLetter 'C'
        $result | Should -BeOfType [bool]
    }

    It 'should return true or false for system drive' {
        # On a real system, C: should return a valid boolean
        $result = Test-IsSSD -DriveLetter 'C'
        $result | Should -BeIn @($true, $false)
    }

    It 'should return false for nonexistent drive (graceful fallback)' {
        Test-IsSSD -DriveLetter 'Z' | Should -BeFalse
    }

    It 'should return false on error (graceful fallback)' {
        Mock -CommandName Get-Partition -MockWith { throw 'Drive not found' }
        Test-IsSSD -DriveLetter 'Z' | Should -BeFalse
    }
}

Describe 'Get-ChassisType' {
    It 'should return Desktop for desktop chassis types' {
        Mock -CommandName Get-CimInstance -MockWith {
            [PSCustomObject]@{ ChassisTypes = @(3) }
        }
        Get-ChassisType | Should -Be 'Desktop'
    }

    It 'should return Laptop for laptop chassis types' {
        Mock -CommandName Get-CimInstance -MockWith {
            [PSCustomObject]@{ ChassisTypes = @(9) }
        }
        Get-ChassisType | Should -Be 'Laptop'
    }

    It 'should return Laptop for portable chassis type 10' {
        Mock -CommandName Get-CimInstance -MockWith {
            [PSCustomObject]@{ ChassisTypes = @(10) }
        }
        Get-ChassisType | Should -Be 'Laptop'
    }

    It 'should return Tablet for chassis type 17' {
        Mock -CommandName Get-CimInstance -MockWith {
            [PSCustomObject]@{ ChassisTypes = @(17) }
        }
        Get-ChassisType | Should -Be 'Tablet'
    }

    It 'should default to Desktop on error' {
        Mock -CommandName Get-CimInstance -MockWith { throw 'WMI error' }
        Get-ChassisType | Should -Be 'Desktop'
    }
}

Describe 'Test-FeatureExists' {
    It 'should return true when registry key exists (no ValueName)' {
        Mock -CommandName Test-Path -MockWith { $true }
        Test-FeatureExists -RegistryPath 'HKLM:\SOFTWARE\Test' | Should -BeTrue
    }

    It 'should return false when registry key does not exist' {
        Mock -CommandName Test-Path -MockWith { $false }
        Test-FeatureExists -RegistryPath 'HKLM:\SOFTWARE\Nonexistent' | Should -BeFalse
    }

    It 'should return true when registry value exists' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Get-ItemProperty -MockWith { [PSCustomObject]@{ TestValue = 1 } }
        Test-FeatureExists -RegistryPath 'HKLM:\SOFTWARE\Test' -ValueName 'TestValue' | Should -BeTrue
    }

    It 'should return false when registry value does not exist' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Get-ItemProperty -MockWith { $null }
        Test-FeatureExists -RegistryPath 'HKLM:\SOFTWARE\Test' -ValueName 'Missing' | Should -BeFalse
    }

    It 'should return false on error (graceful fallback)' {
        Mock -CommandName Test-Path -MockWith { throw 'Access denied' }
        Test-FeatureExists -RegistryPath 'HKLM:\SOFTWARE\Protected' | Should -BeFalse
    }
}
