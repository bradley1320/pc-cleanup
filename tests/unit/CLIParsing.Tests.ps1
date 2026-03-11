BeforeAll {
    # CLI parsing tests verify that main.ps1's parameter definitions are correct.
    # We don't actually invoke main.ps1 (it loads all modules and dispatches),
    # but we verify the param block parses correctly and validates inputs.

    $mainScript = Get-Content -Path "$PSScriptRoot/../../src/main.ps1" -Raw
}

Describe 'main.ps1 parameter definitions' {
    It 'should have a valid param block' {
        $mainScript | Should -Match 'param\s*\('
    }

    It 'should define ProfileName parameter with ValidateSet' {
        $mainScript | Should -BeLike "*ValidateSet('Safe', 'Gaming', 'Privacy', 'Custom')*"
    }

    It 'should define Module parameter with ValidateSet' {
        $mainScript | Should -BeLike "*ValidateSet('QuickClean', 'Startup', 'Performance', 'Privacy'*"
    }

    It 'should define Risk parameter with ValidateSet' {
        $mainScript | Should -BeLike "*ValidateSet('safe', 'moderate', 'advanced')*"
    }

    It 'should define WhatIf as a switch' {
        $mainScript | Should -BeLike '*`[switch`]$WhatIf*'
    }

    It 'should define Undo as a string' {
        $mainScript | Should -BeLike '*`[string`]$Undo*'
    }

    It 'should define Report as a switch' {
        $mainScript | Should -BeLike '*`[switch`]$Report*'
    }

    It 'should define Snapshot with ValidateSet' {
        $mainScript | Should -BeLike "*ValidateSet('Before', 'After', 'Compare')*"
    }

    It 'should default Risk to safe' {
        $mainScript | Should -BeLike "*Risk = 'safe'*"
    }
}

Describe 'main.ps1 module loading' {
    It 'should load core modules in sorted order' {
        $mainScript | Should -Match 'Sort-Object Name'
    }

    It 'should load from PSScriptRoot paths' {
        $mainScript | Should -BeLike '*$PSScriptRoot*'
    }

    It 'should load core, handlers, modules, and ui' {
        $mainScript | Should -BeLike "*Join-Path*'core'*"
        $mainScript | Should -BeLike "*Join-Path*'handlers'*"
        $mainScript | Should -BeLike "*Join-Path*'modules'*"
        $mainScript | Should -BeLike "*Join-Path*'ui'*"
    }
}

Describe 'main.ps1 CLI dispatch' {
    It 'should handle -Undo All' {
        $mainScript | Should -BeLike "*Undo -eq 'All'*"
        $mainScript | Should -Match 'Invoke-UndoAll'
    }

    It 'should handle -Undo with specific tweak name' {
        $mainScript | Should -BeLike '*Invoke-UndoTweak -Name $Undo*'
    }

    It 'should handle -Snapshot modes' {
        $mainScript | Should -BeLike "*Save-SystemSnapshot -Label 'Before'*"
        $mainScript | Should -BeLike "*Save-SystemSnapshot -Label 'After'*"
        $mainScript | Should -Match 'Compare-Snapshots'
    }

    It 'should handle -Report flag' {
        $mainScript | Should -Match 'Get-SecurityReport'
    }

    It 'should handle -Profile Custom by launching interactive menu' {
        $mainScript | Should -BeLike "*ProfileName -eq 'Custom'*"
        $mainScript | Should -Match 'Invoke-MenuLoop'
    }

    It 'should handle -Profile with profiles.json' {
        $mainScript | Should -Match 'profiles\.json'
    }

    It 'should handle -Module dispatch' {
        $mainScript | Should -BeLike '*switch ($Module)*'
    }

    It 'should default to interactive menu' {
        $mainScript | Should -BeLike '*Invoke-MenuLoop*'
    }
}

Describe 'main.ps1 config integrity' {
    It 'should define Test-ConfigIntegrity function' {
        $mainScript | Should -BeLike '*function Test-ConfigIntegrity*'
    }

    It 'should define ExpectedConfigHashes variable' {
        $mainScript | Should -BeLike '*ExpectedConfigHashes*'
    }

    It 'should call Test-ConfigIntegrity before CLI dispatch' {
        $mainScript | Should -BeLike '*Test-ConfigIntegrity*CLI Dispatch*'
    }

    It 'should check SHA256 hashes of config files' {
        $mainScript | Should -BeLike '*Get-FileHash*SHA256*'
    }

    It 'should warn about modified config files' {
        $mainScript | Should -BeLike '*Configuration files have been modified*'
    }

    It 'should require user acknowledgment on hash mismatch' {
        $mainScript | Should -BeLike '*Continue anyway*'
    }
}

Describe 'Test-ConfigIntegrity function' {
    BeforeAll {
        # Extract Test-ConfigIntegrity from main.ps1 without running side effects
        $script:ExpectedConfigHashes = @{}
        $mainLines = Get-Content -Path "$PSScriptRoot/../../src/main.ps1"
        $inFunc = $false
        $funcLines = @()
        $depth = 0
        foreach ($line in $mainLines) {
            if ($line -match '^\s*function Test-ConfigIntegrity') {
                $inFunc = $true
            }
            if ($inFunc) {
                $funcLines += $line
                foreach ($ch in $line.ToCharArray()) {
                    if ($ch -eq '{') { $depth++ }
                    if ($ch -eq '}') { $depth-- }
                }
                if ($depth -le 0 -and $funcLines.Count -gt 1) { break }
            }
        }
        Invoke-Expression ($funcLines -join "`n")
    }

    BeforeEach {
        # Set ConfigPath so the function can resolve config dir in test context
        # (where $PSScriptRoot is empty for Invoke-Expression'd functions)
        $script:ConfigPath = Join-Path "$PSScriptRoot" '../../config'
    }

    It 'should return true when no hashes are embedded (dev mode)' {
        $script:ExpectedConfigHashes = @{}
        Test-ConfigIntegrity | Should -BeTrue
    }

    It 'should return true when all hashes match' {
        $hash = (Get-FileHash -Path (Join-Path $script:ConfigPath 'tweaks.json') -Algorithm SHA256).Hash
        $script:ExpectedConfigHashes = @{ 'tweaks.json' = $hash }
        Test-ConfigIntegrity | Should -BeTrue
    }

    It 'should return false when user rejects modified config' {
        $script:ExpectedConfigHashes = @{ 'tweaks.json' = 'WRONG_HASH_VALUE_HERE' }
        Mock Read-Host { return 'N' }
        Mock Write-Host {}
        Test-ConfigIntegrity | Should -BeFalse
    }

    It 'should hard-block when tweaks.json is tampered (no user bypass)' {
        $script:ExpectedConfigHashes = @{ 'tweaks.json' = 'WRONG_HASH_VALUE_HERE' }
        Mock Write-Host {}
        Test-ConfigIntegrity | Should -BeFalse
    }

    It 'should allow user bypass for non-critical config tampering' {
        $script:ExpectedConfigHashes = @{ 'profiles.json' = 'WRONG_HASH_VALUE_HERE' }
        Mock Read-Host { return 'Y' }
        Mock Write-Host {}
        Test-ConfigIntegrity | Should -BeTrue
    }

    It 'should detect missing config files' {
        $script:ConfigPath = Join-Path $TestDrive 'empty_config'
        New-Item -ItemType Directory -Path $script:ConfigPath -Force | Out-Null
        $script:ExpectedConfigHashes = @{ 'missing.json' = 'HASH' }
        Mock Read-Host { return 'N' }
        Mock Write-Host {}
        Test-ConfigIntegrity | Should -BeFalse
    }
}

Describe 'main.ps1 profile risk clamping' {
    It 'should contain hardcoded max risk per profile name' {
        $mainScript | Should -BeLike '*maxRiskPerProfile*'
    }

    It 'should clamp Safe profile to safe risk' {
        $mainScript | Should -BeLike "*'Safe' = 'safe'*"
    }

    It 'should clamp Gaming profile to safe risk' {
        $mainScript | Should -BeLike "*'Gaming' = 'safe'*"
    }

    It 'should clamp Privacy profile to moderate risk' {
        $mainScript | Should -BeLike "*'Privacy' = 'moderate'*"
    }

    It 'should warn when clamping elevated risk' {
        $mainScript | Should -BeLike '*elevated risk*Clamping*'
    }
}

Describe 'profiles.json' {
    BeforeAll {
        $profilesPath = "$PSScriptRoot/../../config/profiles.json"
        $profilesData = Get-Content -Path $profilesPath -Raw | ConvertFrom-Json
    }

    It 'should be valid JSON' {
        $profilesData | Should -Not -BeNullOrEmpty
    }

    It 'should contain Safe profile' {
        $profilesData.Safe | Should -Not -BeNullOrEmpty
        $profilesData.Safe.risk | Should -Be 'safe'
    }

    It 'should contain Gaming profile' {
        $profilesData.Gaming | Should -Not -BeNullOrEmpty
        $profilesData.Gaming.risk | Should -Be 'safe'
    }

    It 'should contain Privacy profile' {
        $profilesData.Privacy | Should -Not -BeNullOrEmpty
        $profilesData.Privacy.risk | Should -Be 'moderate'
    }

    It 'should contain Custom profile' {
        $profilesData.Custom | Should -Not -BeNullOrEmpty
    }

    It 'should exclude Network from all preset profiles' {
        $profilesData.Safe.excludeModules | Should -Contain 'Network'
        $profilesData.Gaming.excludeModules | Should -Contain 'Network'
        $profilesData.Privacy.excludeModules | Should -Contain 'Network'
    }

    It 'should have description for each profile' {
        $profilesData.Safe.description | Should -Not -BeNullOrEmpty
        $profilesData.Gaming.description | Should -Not -BeNullOrEmpty
        $profilesData.Privacy.description | Should -Not -BeNullOrEmpty
        $profilesData.Custom.description | Should -Not -BeNullOrEmpty
    }
}
