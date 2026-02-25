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
