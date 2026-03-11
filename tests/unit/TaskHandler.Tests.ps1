# ==============================================================================
# PC Cleanup v2 — TaskHandler Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/handlers/TaskHandler.ps1"
}

Describe 'Set-PCCleanupScheduledTask' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should skip when task does not exist' {
        Mock -CommandName Get-ScheduledTask -MockWith { $null }
        Set-PCCleanupScheduledTask -TaskPath '\Microsoft\Windows\TestTask\FakeTask' -Enabled $false
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*not found*' }
    }

    It 'should disable a task when Enabled is false' {
        Mock -CommandName Get-ScheduledTask -MockWith {
            [PSCustomObject]@{ TaskName = 'TestTask'; State = 'Ready' }
        }
        Mock -CommandName Disable-ScheduledTask -MockWith {}
        Set-PCCleanupScheduledTask -TaskPath '\Microsoft\Windows\Test\TestTask' -Enabled $false
        Should -Invoke Disable-ScheduledTask -Times 1
    }

    It 'should enable a task when Enabled is true' {
        Mock -CommandName Get-ScheduledTask -MockWith {
            [PSCustomObject]@{ TaskName = 'TestTask'; State = 'Disabled' }
        }
        Mock -CommandName Enable-ScheduledTask -MockWith {}
        Set-PCCleanupScheduledTask -TaskPath '\Microsoft\Windows\Test\TestTask' -Enabled $true
        Should -Invoke Enable-ScheduledTask -Times 1
    }

    It 'should handle Access Denied gracefully' {
        Mock -CommandName Get-ScheduledTask -MockWith {
            [PSCustomObject]@{ TaskName = 'ProtectedTask'; State = 'Ready' }
        }
        Mock -CommandName Disable-ScheduledTask -MockWith {
            throw [System.UnauthorizedAccessException]::new('Access denied')
        }
        { Set-PCCleanupScheduledTask -TaskPath '\Microsoft\Windows\Test\ProtectedTask' -Enabled $false } | Should -Not -Throw
    }

    It 'should handle general errors gracefully' {
        Mock -CommandName Get-ScheduledTask -MockWith {
            [PSCustomObject]@{ TaskName = 'BrokenTask'; State = 'Ready' }
        }
        Mock -CommandName Disable-ScheduledTask -MockWith { throw 'Unexpected error' }
        { Set-PCCleanupScheduledTask -TaskPath '\Microsoft\Windows\Test\BrokenTask' -Enabled $false } | Should -Not -Throw
    }

    It 'should log the operation result' {
        Mock -CommandName Get-ScheduledTask -MockWith {
            [PSCustomObject]@{ TaskName = 'LoggedTask'; State = 'Ready' }
        }
        Mock -CommandName Disable-ScheduledTask -MockWith {}
        Set-PCCleanupScheduledTask -TaskPath '\Microsoft\Windows\Test\LoggedTask' -Enabled $false
        Should -Invoke Write-Log -Times 1 -ParameterFilter { $Message -like '*ScheduledTask*' }
    }

    It 'should show success message after disabling' {
        Mock -CommandName Get-ScheduledTask -MockWith {
            [PSCustomObject]@{ TaskName = 'SuccessTask'; State = 'Ready' }
        }
        Mock -CommandName Disable-ScheduledTask -MockWith {}
        Set-PCCleanupScheduledTask -TaskPath '\Microsoft\Windows\Test\SuccessTask' -Enabled $false
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Disabled*SuccessTask*' -and $ForegroundColor -eq 'Green' }
    }

    It 'should show success message after enabling' {
        Mock -CommandName Get-ScheduledTask -MockWith {
            [PSCustomObject]@{ TaskName = 'EnableTask'; State = 'Disabled' }
        }
        Mock -CommandName Enable-ScheduledTask -MockWith {}
        Set-PCCleanupScheduledTask -TaskPath '\Microsoft\Windows\Test\EnableTask' -Enabled $true
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*Enabled*EnableTask*' -and $ForegroundColor -eq 'Green' }
    }
}
