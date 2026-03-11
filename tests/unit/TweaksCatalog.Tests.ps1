# ==============================================================================
# PC Cleanup v2 -- TweaksCatalog Tests (Pester 5.x)
# Validates the REAL config/tweaks.json against the expected schema and
# council-mandated requirements.
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
    . "$PSScriptRoot/../../src/core/05-UndoManager.ps1"
    . "$PSScriptRoot/../../src/core/04-TweakEngine.ps1"
    . "$PSScriptRoot/../../src/handlers/RegistryHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ServiceHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/TaskHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ScriptHandler.ps1"
}

Describe 'Tweaks Catalog Validation' {
    BeforeAll {
        # Point at the real config
        $script:ConfigPath = Join-Path $PSScriptRoot '../../config'
        $tweaksPath = Join-Path $script:ConfigPath 'tweaks.json'
        $raw = Get-Content -Path $tweaksPath -Raw | ConvertFrom-Json

        # Parse all tweaks into array
        $script:AllTweaks = @()
        foreach ($prop in $raw.PSObject.Properties) {
            if ($prop.Name.StartsWith('_')) { continue }
            $tweak = $prop.Value
            $tweak | Add-Member -NotePropertyName 'Id' -NotePropertyValue $prop.Name -Force
            $script:AllTweaks += $tweak
        }
    }

    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        $script:SchemaValidated = $false
    }

    It 'should have exactly 29 total tweaks' {
        $script:AllTweaks.Count | Should -Be 29
    }

    It 'should have 18 safe-tier tweaks' {
        @($script:AllTweaks | Where-Object { $_.risk -eq 'safe' }).Count | Should -Be 18
    }

    It 'should have 8 moderate-tier tweaks' {
        @($script:AllTweaks | Where-Object { $_.risk -eq 'moderate' }).Count | Should -Be 8
    }

    It 'should have 3 advanced-tier tweaks' {
        @($script:AllTweaks | Where-Object { $_.risk -eq 'advanced' }).Count | Should -Be 3
    }

    It 'every tweak should have required top-level fields' {
        foreach ($tweak in $script:AllTweaks) {
            $tweak.name        | Should -Not -BeNullOrEmpty -Because "$($tweak.Id) must have 'name'"
            $tweak.description | Should -Not -BeNullOrEmpty -Because "$($tweak.Id) must have 'description'"
            $tweak.detail      | Should -Not -BeNullOrEmpty -Because "$($tweak.Id) must have 'detail'"
            $tweak.docsUrl     | Should -Not -BeNullOrEmpty -Because "$($tweak.Id) must have 'docsUrl'"
            $tweak.category    | Should -Not -BeNullOrEmpty -Because "$($tweak.Id) must have 'category'"
            $tweak.risk        | Should -Not -BeNullOrEmpty -Because "$($tweak.Id) must have 'risk'"
        }
    }

    It 'every docsUrl should start with https://' {
        foreach ($tweak in $script:AllTweaks) {
            $tweak.docsUrl | Should -BeLike 'https://*' -Because "$($tweak.Id) docsUrl must be HTTPS"
        }
    }

    It 'every risk value should be safe, moderate, or advanced' {
        foreach ($tweak in $script:AllTweaks) {
            $tweak.risk | Should -BeIn @('safe', 'moderate', 'advanced') -Because "$($tweak.Id) has invalid risk"
        }
    }

    It 'every registry entry should have a valid type field' {
        $validTypes = @('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')
        foreach ($tweak in $script:AllTweaks) {
            if ($tweak.registry -and $tweak.registry.Count -gt 0) {
                foreach ($reg in $tweak.registry) {
                    $reg.type | Should -BeIn $validTypes -Because "$($tweak.Id) registry entry '$($reg.name)' has invalid type"
                }
            }
        }
    }

    It 'every registry path should start with HKLM:\ or HKCU:\' {
        foreach ($tweak in $script:AllTweaks) {
            if ($tweak.registry -and $tweak.registry.Count -gt 0) {
                foreach ($reg in $tweak.registry) {
                    ($reg.path -like 'HKLM:\*' -or $reg.path -like 'HKCU:\*') | Should -BeTrue -Because "$($tweak.Id) registry path '$($reg.path)' must start with HKLM:\ or HKCU:\"
                }
            }
        }
    }

    It 'every registry entry should have a defaultValue' {
        foreach ($tweak in $script:AllTweaks) {
            if ($tweak.registry -and $tweak.registry.Count -gt 0) {
                foreach ($reg in $tweak.registry) {
                    $hasDefault = $reg.PSObject.Properties.Name -contains 'defaultValue'
                    $hasDefault | Should -BeTrue -Because "$($tweak.Id) registry '$($reg.name)' must have defaultValue"
                }
            }
        }
    }

    It 'DWord values should be integers not strings' {
        foreach ($tweak in $script:AllTweaks) {
            if ($tweak.registry -and $tweak.registry.Count -gt 0) {
                foreach ($reg in $tweak.registry) {
                    if ($reg.type -eq 'DWord' -and $reg.value -ne '<RemoveEntry>') {
                        $reg.value | Should -BeOfType [System.ValueType] -Because "$($tweak.Id) DWord '$($reg.name)' value should be numeric"
                    }
                }
            }
        }
    }

    It 'DisableDiagTrack should be moderate tier (council mandate)' {
        $dt = $script:AllTweaks | Where-Object { $_.Id -eq 'DisableDiagTrack' }
        $dt | Should -Not -BeNullOrEmpty
        $dt.risk | Should -Be 'moderate'
    }

    It 'DisableCopilot should be moderate tier (council mandate)' {
        $cp = $script:AllTweaks | Where-Object { $_.Id -eq 'DisableCopilot' }
        $cp | Should -Not -BeNullOrEmpty
        $cp.risk | Should -Be 'moderate'
    }

    It 'DisableRecallAI should be moderate tier (council mandate)' {
        $ra = $script:AllTweaks | Where-Object { $_.Id -eq 'DisableRecallAI' }
        $ra | Should -Not -BeNullOrEmpty
        $ra.risk | Should -Be 'moderate'
    }

    It 'schema validation should pass via Test-TweakSchema' {
        { Test-TweakSchema -Tweaks $script:AllTweaks } | Should -Not -Throw
    }

    It 'all tweaks should be in a valid category' {
        $validCategories = @('Privacy', 'Performance', 'Cleanup')
        foreach ($tweak in $script:AllTweaks) {
            $tweak.category | Should -BeIn $validCategories -Because "$($tweak.Id) should be in a valid category"
        }
    }

    It 'should have 20 Privacy tweaks' {
        @($script:AllTweaks | Where-Object { $_.category -eq 'Privacy' }).Count | Should -Be 20
    }

    It 'should have 9 Performance tweaks' {
        @($script:AllTweaks | Where-Object { $_.category -eq 'Performance' }).Count | Should -Be 9
    }

    It 'UserPreferencesMask should be Binary type (not String)' {
        $perf = $script:AllTweaks | Where-Object { $_.Id -eq 'OptimizeVisualEffects' }
        $perf | Should -Not -BeNullOrEmpty
        $upm = $perf.registry | Where-Object { $_.name -eq 'UserPreferencesMask' }
        $upm | Should -Not -BeNullOrEmpty
        $upm.type | Should -Be 'Binary' -Because 'Windows stores UserPreferencesMask as REG_BINARY'
        @($upm.value).Count | Should -Be 8 -Because 'Binary value should be an 8-byte array'
    }

    It 'BlockTelemetryFirewall should have invokeScript and undoScript' {
        $fw = $script:AllTweaks | Where-Object { $_.Id -eq 'BlockTelemetryFirewall' }
        $fw | Should -Not -BeNullOrEmpty
        $fw.invokeScript.Count | Should -BeGreaterThan 0
        $fw.undoScript.Count | Should -BeGreaterThan 0
    }
}
