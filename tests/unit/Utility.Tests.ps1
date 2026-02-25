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

Describe 'Format-FileSize' {
    It 'should format bytes to KB' {
        Set-ItResult -Pending -Because 'Not implemented yet'
    }

    It 'should format bytes to MB' {
        Set-ItResult -Pending -Because 'Not implemented yet'
    }

    It 'should format bytes to GB' {
        Set-ItResult -Pending -Because 'Not implemented yet'
    }

    It 'should handle zero bytes' {
        Set-ItResult -Pending -Because 'Not implemented yet'
    }
}

Describe 'Get-UserConfirmation' {
    It 'should return boolean' {
        Set-ItResult -Pending -Because 'Not implemented yet'
    }
}

Describe 'Write-Success' {
    It 'should write green text to host' {
        Set-ItResult -Pending -Because 'Not implemented yet'
    }
}

Describe 'Write-Err' {
    It 'should write red text with cause and fix' {
        Set-ItResult -Pending -Because 'Not implemented yet'
    }
}
