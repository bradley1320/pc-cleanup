# ==============================================================================
# PC Cleanup v2 — Utility Tests (Pester 5.x)
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
}

Describe 'Test-IsAdmin' {
    It 'should return a boolean value' {
        $result = Test-IsAdmin
        $result | Should -BeOfType [bool]
    }
}

Describe 'Write-Log' {
    BeforeEach {
        $script:testLogDir = Join-Path $TestDrive 'PCCleanup\logs'
        # Override the log path by mocking env variable resolution
        Mock -CommandName Get-Date -MockWith { [datetime]'2025-06-15 10:30:00' } -ParameterFilter { $Format -eq 'yyyy-MM-dd' }
    }

    It 'should not throw even on valid input' {
        { Write-Log -Message 'Test message' } | Should -Not -Throw
    }

    It 'should not throw when log directory is unwritable' {
        # Write-Log wraps everything in try/catch — should never throw
        Mock -CommandName Add-Content -MockWith { throw 'Disk full' }
        { Write-Log -Message 'Test message' } | Should -Not -Throw
    }
}

Describe 'Write-Success' {
    It 'should write green text to host' {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Write-Success -Message 'Operation completed'
        Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like '*Operation completed*' -and $ForegroundColor -eq 'Green' }
    }

    It 'should call Write-Log with SUCCESS prefix' {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Write-Success -Message 'Test'
        Should -Invoke Write-Log -Times 1 -ParameterFilter { $Message -like '*SUCCESS*Test*' }
    }
}

Describe 'Write-Info' {
    It 'should write cyan text to host' {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Write-Info -Message 'Information here'
        Should -Invoke Write-Host -Times 1 -ParameterFilter { $ForegroundColor -eq 'Cyan' }
    }
}

Describe 'Write-Warn' {
    It 'should write yellow text to host' {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Write-Warn -Message 'Warning here'
        Should -Invoke Write-Host -Times 1 -ParameterFilter { $ForegroundColor -eq 'Yellow' }
    }
}

Describe 'Write-Err' {
    It 'should write red text with cause and fix' {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Write-Err -Message 'Something failed' -Cause 'Bad input' -Fix 'Check your input'
        Should -Invoke Write-Host -Times 1 -ParameterFilter { $ForegroundColor -eq 'Red' }
        Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like '*Why: Bad input*' }
        Should -Invoke Write-Host -Times 1 -ParameterFilter { $Object -like '*Fix: Check your input*' }
    }

    It 'should handle missing cause and fix' {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        { Write-Err -Message 'Error only' } | Should -Not -Throw
        Should -Invoke Write-Host -Times 1
    }
}

Describe 'Write-Skip' {
    It 'should write dark gray text to host' {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Write-Skip -Message 'Skipped operation'
        Should -Invoke Write-Host -Times 1 -ParameterFilter { $ForegroundColor -eq 'DarkGray' }
    }
}

Describe 'Format-FileSize' {
    It 'should format bytes to GB' {
        Format-FileSize -Bytes 2147483648 | Should -Be '2.00 GB'
    }

    It 'should format bytes to MB' {
        Format-FileSize -Bytes 5242880 | Should -Be '5.00 MB'
    }

    It 'should format bytes to KB' {
        Format-FileSize -Bytes 1536 | Should -Be '1.50 KB'
    }

    It 'should handle exact GB boundary' {
        Format-FileSize -Bytes 1073741824 | Should -Be '1.00 GB'
    }

    It 'should handle exact MB boundary' {
        Format-FileSize -Bytes 1048576 | Should -Be '1.00 MB'
    }

    It 'should handle exact KB boundary' {
        Format-FileSize -Bytes 1024 | Should -Be '1.00 KB'
    }

    It 'should handle zero bytes' {
        Format-FileSize -Bytes 0 | Should -Be '0 bytes'
    }

    It 'should handle small byte values' {
        Format-FileSize -Bytes 512 | Should -Be '512 bytes'
    }
}

Describe 'Get-UserConfirmation' {
    It 'should return true when user enters Y' {
        Mock -CommandName Read-Host -MockWith { 'Y' }
        Get-UserConfirmation -Prompt 'Continue?' | Should -BeTrue
    }

    It 'should return true when user enters y (lowercase)' {
        Mock -CommandName Read-Host -MockWith { 'y' }
        Get-UserConfirmation -Prompt 'Continue?' | Should -BeTrue
    }

    It 'should return true when user enters yes' {
        Mock -CommandName Read-Host -MockWith { 'yes' }
        Get-UserConfirmation -Prompt 'Continue?' | Should -BeTrue
    }

    It 'should return false when user enters N' {
        Mock -CommandName Read-Host -MockWith { 'N' }
        Get-UserConfirmation -Prompt 'Continue?' | Should -BeFalse
    }

    It 'should return true on empty input when default is Y' {
        Mock -CommandName Read-Host -MockWith { '' }
        Get-UserConfirmation -Prompt 'Continue?' -Default 'Y' | Should -BeTrue
    }

    It 'should return false on empty input when default is N' {
        Mock -CommandName Read-Host -MockWith { '' }
        Get-UserConfirmation -Prompt 'Continue?' -Default 'N' | Should -BeFalse
    }
}
