# ==============================================================================
# PC Cleanup v2 — ServiceHandler Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/handlers/ServiceHandler.ps1"
}

Describe 'Set-PCCleanupService' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should warn and return when service does not exist' {
        Mock -CommandName Get-Service -MockWith { $null }
        Set-PCCleanupService -Name 'FakeService' -StartupType 'Disabled'
        Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like '*not found*' }
    }

    It 'should stop service first when StopFirst is specified and service is running' {
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'TestSvc'; Status = 'Running'; StartType = 'Automatic' }
        }
        Mock -CommandName Stop-Service -MockWith {}
        Mock -CommandName Set-Service -MockWith {}
        Set-PCCleanupService -Name 'TestSvc' -StartupType 'Disabled' -StopFirst
        Should -Invoke Stop-Service -Times 1
    }

    It 'should not stop service when StopFirst is not specified' {
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'TestSvc'; Status = 'Running'; StartType = 'Automatic' }
        }
        Mock -CommandName Set-Service -MockWith {}
        Mock -CommandName Stop-Service -MockWith {}
        Set-PCCleanupService -Name 'TestSvc' -StartupType 'Manual'
        Should -Invoke Stop-Service -Times 0
    }

    It 'should call Set-Service with correct startup type' {
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'TestSvc'; Status = 'Stopped'; StartType = 'Manual' }
        }
        Mock -CommandName Set-Service -MockWith {}
        Set-PCCleanupService -Name 'TestSvc' -StartupType 'Disabled'
        Should -Invoke Set-Service -Times 1 -ParameterFilter { $StartupType -eq 'Disabled' }
    }

    It 'should warn when service reverts after modification' {
        # First call: initial state. Second call: verification shows revert.
        $script:getServiceCallCount = 0
        Mock -CommandName Get-Service -MockWith {
            $script:getServiceCallCount++
            if ($script:getServiceCallCount -eq 1) {
                [PSCustomObject]@{ Name = 'ProtectedSvc'; Status = 'Running'; StartType = 'Automatic' }
            } else {
                [PSCustomObject]@{ Name = 'ProtectedSvc'; Status = 'Running'; StartType = 'Automatic' }
            }
        }
        Mock -CommandName Set-Service -MockWith {}
        Set-PCCleanupService -Name 'ProtectedSvc' -StartupType 'Disabled'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*may have reverted*' }
    }

    It 'should handle Access Denied gracefully' {
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'ProtectedSvc'; Status = 'Running'; StartType = 'Automatic' }
        }
        Mock -CommandName Set-Service -MockWith { throw [System.UnauthorizedAccessException]::new('Access denied') }
        { Set-PCCleanupService -Name 'ProtectedSvc' -StartupType 'Disabled' } | Should -Not -Throw
    }

    It 'should handle general errors gracefully' {
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'BrokenSvc'; Status = 'Running'; StartType = 'Automatic' }
        }
        Mock -CommandName Set-Service -MockWith { throw 'Something broke' }
        { Set-PCCleanupService -Name 'BrokenSvc' -StartupType 'Disabled' } | Should -Not -Throw
    }

    It 'should confirm success when service changes correctly' {
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'GoodSvc'; Status = 'Stopped'; StartType = 'Disabled' }
        }
        Mock -CommandName Set-Service -MockWith {}
        Set-PCCleanupService -Name 'GoodSvc' -StartupType 'Disabled'
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*set to*Disabled*' -and $ForegroundColor -eq 'Green' }
    }
}
