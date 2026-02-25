BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/modules/NetworkReset.ps1"
}

Describe 'Reset-DNSCache' {
    It 'should return $true on success' {
        Mock ipconfig { 'Successfully flushed the DNS Resolver Cache.' }
        # ipconfig doesn't set LASTEXITCODE reliably, mock the global
        $global:LASTEXITCODE = 0
        $result = Reset-DNSCache
        $result | Should -Be $true
    }

    It 'should return $true in WhatIf mode without executing' {
        Mock ipconfig { throw 'Should not be called' }
        $result = Reset-DNSCache -WhatIf
        $result | Should -Be $true
    }
}

Describe 'Reset-WinsockCatalog' {
    It 'should require admin' {
        Mock Test-IsAdmin { return $false }
        $result = Reset-WinsockCatalog
        $result | Should -Be $false
    }

    It 'should return $true on success when admin' {
        Mock Test-IsAdmin { return $true }
        Mock netsh { 'Winsock Catalog Reset completed.' }
        $global:LASTEXITCODE = 0
        $result = Reset-WinsockCatalog
        $result | Should -Be $true
    }

    It 'should return $true in WhatIf mode' {
        Mock Test-IsAdmin { return $true }
        Mock netsh { throw 'Should not be called' }
        $result = Reset-WinsockCatalog -WhatIf
        $result | Should -Be $true
    }
}

Describe 'Reset-TCPIPStack' {
    It 'should require admin' {
        Mock Test-IsAdmin { return $false }
        $result = Reset-TCPIPStack
        $result | Should -Be $false
    }

    It 'should return $true on success when admin' {
        Mock Test-IsAdmin { return $true }
        Mock netsh { 'Resetting OK!' }
        $global:LASTEXITCODE = 0
        $result = Reset-TCPIPStack
        $result | Should -Be $true
    }

    It 'should return $true in WhatIf mode' {
        Mock Test-IsAdmin { return $true }
        Mock netsh { throw 'Should not be called' }
        $result = Reset-TCPIPStack -WhatIf
        $result | Should -Be $true
    }
}

Describe 'Clear-ARPCache' {
    It 'should require admin' {
        Mock Test-IsAdmin { return $false }
        $result = Clear-ARPCache
        $result | Should -Be $false
    }

    It 'should return $true on success when admin' {
        Mock Test-IsAdmin { return $true }
        Mock netsh { 'OK' }
        $global:LASTEXITCODE = 0
        $result = Clear-ARPCache
        $result | Should -Be $true
    }

    It 'should return $true in WhatIf mode' {
        Mock Test-IsAdmin { return $true }
        Mock netsh { throw 'Should not be called' }
        $result = Clear-ARPCache -WhatIf
        $result | Should -Be $true
    }
}

Describe 'Show-NetworkResetMenu' {
    It 'should return without error when user presses Enter' {
        Mock Read-Host { return '' }
        { Show-NetworkResetMenu } | Should -Not -Throw
    }

    It 'should return without error when user presses B' {
        Mock Read-Host { return 'B' }
        { Show-NetworkResetMenu } | Should -Not -Throw
    }

    It 'should handle WhatIf mode' {
        Mock Read-Host { return '1' }
        Mock Reset-DNSCache { return $true }
        { Show-NetworkResetMenu -WhatIf } | Should -Not -Throw
    }
}
