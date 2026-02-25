# ==============================================================================
# PC Cleanup v2 — RegistryHandler Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/handlers/RegistryHandler.ps1"
}

Describe 'Set-PCCleanupRegistry' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should create registry key path if it does not exist' {
        Mock -CommandName Test-Path -MockWith { $false }
        Mock -CommandName New-Item -MockWith {}
        Mock -CommandName Set-ItemProperty -MockWith {}
        Set-PCCleanupRegistry -Path 'HKLM:\SOFTWARE\Test' -Name 'Value1' -Value 1 -Type 'DWord'
        Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -eq 'HKLM:\SOFTWARE\Test' }
    }

    It 'should not create key path if it already exists' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName New-Item -MockWith {}
        Mock -CommandName Set-ItemProperty -MockWith {}
        Set-PCCleanupRegistry -Path 'HKLM:\SOFTWARE\Existing' -Name 'Value1' -Value 1 -Type 'DWord'
        Should -Invoke New-Item -Times 0
    }

    It 'should set DWord value with explicit type' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Set-ItemProperty -MockWith {}
        Set-PCCleanupRegistry -Path 'HKLM:\SOFTWARE\Test' -Name 'DWordVal' -Value 42 -Type 'DWord'
        Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Type -eq 'DWord' }
    }

    It 'should set QWord value with explicit type' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Set-ItemProperty -MockWith {}
        Set-PCCleanupRegistry -Path 'HKLM:\SOFTWARE\Test' -Name 'QWordVal' -Value 9999999999 -Type 'QWord'
        Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Type -eq 'QWord' }
    }

    It 'should set String value with explicit type' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Set-ItemProperty -MockWith {}
        Set-PCCleanupRegistry -Path 'HKLM:\SOFTWARE\Test' -Name 'StringVal' -Value 'hello' -Type 'String'
        Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Type -eq 'String' }
    }

    It 'should set ExpandString value with explicit type' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Set-ItemProperty -MockWith {}
        Set-PCCleanupRegistry -Path 'HKLM:\SOFTWARE\Test' -Name 'ExpandVal' -Value '%SystemRoot%\test' -Type 'ExpandString'
        Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter { $Type -eq 'ExpandString' }
    }

    It 'should delete value when given <RemoveEntry> sentinel' {
        Mock -CommandName Remove-ItemProperty -MockWith {}
        Mock -CommandName Set-ItemProperty -MockWith {}
        Set-PCCleanupRegistry -Path 'HKLM:\SOFTWARE\Test' -Name 'ToRemove' -Value '<RemoveEntry>' -Type 'DWord'
        Should -Invoke Remove-ItemProperty -Times 1
        Should -Invoke Set-ItemProperty -Times 0
    }

    It 'should catch TrustedInstaller Access Denied gracefully' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Set-ItemProperty -MockWith { throw [System.UnauthorizedAccessException]::new('Access denied') }
        { Set-PCCleanupRegistry -Path 'HKLM:\SOFTWARE\Protected' -Name 'Val' -Value 0 -Type 'DWord' } | Should -Not -Throw
    }

    It 'should catch general errors gracefully' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Set-ItemProperty -MockWith { throw 'Something went wrong' }
        { Set-PCCleanupRegistry -Path 'HKLM:\SOFTWARE\Bad' -Name 'Val' -Value 0 -Type 'DWord' } | Should -Not -Throw
    }

    It 'should log every registry modification' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Set-ItemProperty -MockWith {}
        Set-PCCleanupRegistry -Path 'HKLM:\SOFTWARE\Test' -Name 'Logged' -Value 1 -Type 'DWord'
        Should -Invoke Write-Log -Times 1 -ParameterFilter { $Message -like '*Registry:*Set*' }
    }

    It 'should handle DWord value 0 correctly (not treat as falsy)' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Set-ItemProperty -MockWith {}
        { Set-PCCleanupRegistry -Path 'HKLM:\SOFTWARE\Test' -Name 'Zero' -Value 0 -Type 'DWord' } | Should -Not -Throw
        Should -Invoke Set-ItemProperty -Times 1
    }
}

Describe 'Get-PCCleanupRegistryValue' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should return Exists=$false for non-existent path' {
        Mock -CommandName Test-Path -MockWith { $false }
        $result = Get-PCCleanupRegistryValue -Path 'HKLM:\SOFTWARE\Nonexistent' -Name 'Missing'
        $result.Exists | Should -BeFalse
        $result.Value | Should -BeNullOrEmpty
        $result.Type | Should -BeNullOrEmpty
    }

    It 'should return a PSCustomObject with expected properties' {
        # This test uses a real registry path that should exist on any Windows system
        $result = Get-PCCleanupRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'CurrentBuildNumber'
        $result.PSObject.Properties.Name | Should -Contain 'Value'
        $result.PSObject.Properties.Name | Should -Contain 'Type'
        $result.PSObject.Properties.Name | Should -Contain 'Exists'
    }
}
