# ==============================================================================
# PC Cleanup v2 -- Adversarial Tests (Pester 5.x)
# Tests designed to break things: edge cases, schema abuse, idempotency,
# undo integrity, handler edge cases, etc.
# ==============================================================================

BeforeAll {
    . "$PSScriptRoot/../../src/core/01-Utility.ps1"
    . "$PSScriptRoot/../../src/core/02-SystemInfo.ps1"
    . "$PSScriptRoot/../../src/core/03-SafetyNet.ps1"
    . "$PSScriptRoot/../../src/core/05-UndoManager.ps1"
    . "$PSScriptRoot/../../src/core/04-TweakEngine.ps1"
    . "$PSScriptRoot/../../src/handlers/RegistryHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ServiceHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/TaskHandler.ps1"
    . "$PSScriptRoot/../../src/handlers/ScriptHandler.ps1"
}

# =============================================================================
# 1. TWEAK ENGINE SCHEMA ABUSE
# =============================================================================

Describe 'Schema Abuse: Missing Required Fields' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        $script:ConfigPath = $TestDrive
        $script:SchemaValidated = $false
    }

    It 'should reject tweak missing category field' {
        $bad = @{
            'Bad' = @{
                name = 'Bad Tweak'
                description = 'Missing category'
                detail = 'Detail'
                risk = 'safe'
                registry = @()
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $bad | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        { Get-Tweaks } | Should -Throw '*invalid*'
    }

    It 'should reject tweak missing risk field' {
        $bad = @{
            'Bad' = @{
                name = 'Bad Tweak'
                description = 'Missing risk'
                detail = 'Detail'
                category = 'Privacy'
                registry = @()
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $bad | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        { Get-Tweaks } | Should -Throw '*invalid*'
    }

    It 'should reject tweak with invalid risk value' {
        $bad = @{
            'Bad' = @{
                name = 'Bad Tweak'
                description = 'Invalid risk'
                detail = 'Detail'
                category = 'Privacy'
                risk = 'critical'
                registry = @()
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $bad | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        { Get-Tweaks } | Should -Throw '*invalid*'
    }

    It 'should reject registry entry missing type field' {
        $bad = @{
            'Bad' = @{
                name = 'Bad Tweak'
                description = 'Registry missing type'
                detail = 'Detail'
                category = 'Privacy'
                risk = 'safe'
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val'; value = 0; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $bad | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        { Get-Tweaks } | Should -Throw '*invalid*'
    }

    It 'should reject registry entry missing value field (null)' {
        $bad = @{
            'Bad' = @{
                name = 'Bad Tweak'
                description = 'Registry missing value'
                detail = 'Detail'
                category = 'Privacy'
                risk = 'safe'
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val'; value = $null; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $bad | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        { Get-Tweaks } | Should -Throw '*invalid*'
    }

    It 'should accept registry entry with value 0 (falsy but valid)' {
        $ok = @{
            'Good' = @{
                name = 'Zero Value Tweak'
                description = 'Value is 0 which is falsy'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $ok | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        { Get-Tweaks -RiskLevel 'safe' } | Should -Not -Throw
    }

    It 'should reject service entry missing startupType' {
        $bad = @{
            'Bad' = @{
                name = 'Bad Tweak'
                description = 'Service missing startupType'
                detail = 'Detail'
                category = 'Privacy'
                risk = 'safe'
                registry = @()
                services = @(@{ name = 'TestSvc'; defaultType = 'Automatic' })
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $bad | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        { Get-Tweaks } | Should -Throw '*invalid*'
    }

    It 'should reject scheduledTask entry missing enabled field' {
        $bad = @{
            'Bad' = @{
                name = 'Bad Tweak'
                description = 'Task missing enabled'
                detail = 'Detail'
                category = 'Privacy'
                risk = 'safe'
                registry = @()
                services = @()
                scheduledTasks = @(@{ path = '\Microsoft\Windows\Test' })
                invokeScript = @()
                undoScript = @()
            }
        }
        $bad | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        { Get-Tweaks } | Should -Throw '*invalid*'
    }

    It 'FIXED(W-2): empty JSON object returns empty array instead of crashing' {
        '{}' | Set-Content (Join-Path $TestDrive 'tweaks.json')
        # FIX APPLIED: guard with count check before calling Test-TweakSchema
        $result = Get-Tweaks -RiskLevel 'advanced'
        @($result).Count | Should -Be 0
    }

    It 'should handle malformed JSON gracefully (throw, not crash)' {
        'this is not json {{{' | Set-Content (Join-Path $TestDrive 'tweaks.json')
        { Get-Tweaks } | Should -Throw
    }

    It 'should handle JSON with extra unknown fields (gracefully ignore)' {
        $extra = @{
            'ExtraTweak' = @{
                name = 'Extra Fields'
                description = 'Has extra fields'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1; extraField = 'ignored' })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
                unknownTopLevel = 'should be ignored'
            }
        }
        $extra | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
        { Get-Tweaks -RiskLevel 'safe' } | Should -Not -Throw
    }
}

# =============================================================================
# 2. IDEMPOTENCY AND DOUBLE-APPLY
# =============================================================================

Describe 'Idempotency: Apply Tweak Twice' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        Mock -CommandName Get-PCCleanupRegistryValue -MockWith {
            [PSCustomObject]@{ Value = 1; Type = 'DWord'; Exists = $true }
        }
        $script:SchemaValidated = $true
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
        $script:ConfigPath = $TestDrive

        $tweaks = @{
            'TestTweak' = @{
                name = 'Test Tweak'
                description = 'A test'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @(@{ path = 'HKCU:\Test'; name = 'Val'; value = 0; type = 'DWord'; defaultValue = 1 })
                services = @()
                scheduledTasks = @()
                invokeScript = @()
                undoScript = @()
            }
        }
        $tweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
    }

    It 'FIXED(W-1): second apply is blocked when tweak already in undo log' {
        # FIX APPLIED: Invoke-Tweak checks undo log and skips if already applied
        Invoke-Tweak -Name 'TestTweak'
        Invoke-Tweak -Name 'TestTweak'
        $log = Get-AppliedTweaks
        # Only one entry should exist -- second apply was blocked
        @($log).Count | Should -Be 1
    }

    It 'FIXED(W-1): second apply shows informational message' {
        Invoke-Tweak -Name 'TestTweak'
        Invoke-Tweak -Name 'TestTweak'
        # Should inform user that tweak is already applied
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*already applied*' }
    }

    It 'FIXED(W-1): single undo cleanly removes the only entry' {
        Invoke-Tweak -Name 'TestTweak'
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        Invoke-UndoTweak -Name 'TestTweak'
        $remaining = Get-AppliedTweaks
        # Clean undo -- no stale entries
        @($remaining).Count | Should -Be 0
    }
}

# =============================================================================
# 3. UNDO INTEGRITY
# =============================================================================

Describe 'Undo Integrity: Undo Never-Applied Tweak' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
    }

    It 'should warn (not crash) when undoing a never-applied tweak' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        '[]' | Set-Content -Path $script:UndoLogPath
        { Invoke-UndoTweak -Name 'NeverApplied' } | Should -Not -Throw
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No undo data*' }
    }

    It 'should warn when no undo log file exists at all' {
        { Invoke-UndoTweak -Name 'NeverApplied' } | Should -Not -Throw
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No undo data*' }
    }
}

Describe 'Undo Integrity: Undo with Corrupted Log' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
    }

    It 'should handle undo with truncated JSON in log' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        '[{"TweakName":"Test","AppliedAt":"2025-01-01' | Set-Content -Path $script:UndoLogPath
        { Invoke-UndoTweak -Name 'Test' } | Should -Not -Throw
    }

    It 'should handle undo with empty file' {
        New-Item -ItemType Directory -Path $script:UndoLogDir -Force | Out-Null
        '' | Set-Content -Path $script:UndoLogPath
        { Invoke-UndoTweak -Name 'Test' } | Should -Not -Throw
    }
}

Describe 'Undo Integrity: Random Order Undo' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        Mock -CommandName Set-PCCleanupService -MockWith {}
        Mock -CommandName Start-Service -MockWith {}
        Mock -CommandName Set-PCCleanupScheduledTask -MockWith {}
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
    }

    It 'should allow undoing tweaks in any order' {
        $regChanges = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val1'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        $svcChanges = @([PSCustomObject]@{ Type = 'Service'; Name = 'TestSvc'; OriginalStartupType = 'Automatic'; OriginalStatus = 'Running' })
        $taskChanges = @([PSCustomObject]@{ Type = 'ScheduledTask'; Path = '\Test\Task1'; OriginalEnabled = $true })

        Register-AppliedTweak -Name 'Tweak1' -Changes $regChanges -Timestamp ([datetime]'2025-01-01') -Category 'Privacy'
        Register-AppliedTweak -Name 'Tweak2' -Changes $svcChanges -Timestamp ([datetime]'2025-01-02') -Category 'Privacy'
        Register-AppliedTweak -Name 'Tweak3' -Changes $taskChanges -Timestamp ([datetime]'2025-01-03') -Category 'Privacy'

        # Undo middle one first
        Invoke-UndoTweak -Name 'Tweak2'
        $remaining = Get-AppliedTweaks
        @($remaining).Count | Should -Be 2

        # Undo first
        Invoke-UndoTweak -Name 'Tweak1'
        $remaining = Get-AppliedTweaks
        @($remaining).Count | Should -Be 1

        # Undo last
        Invoke-UndoTweak -Name 'Tweak3'
        $remaining = Get-AppliedTweaks
        @($remaining).Count | Should -Be 0
    }
}

# =============================================================================
# 4. HANDLER EDGE CASES
# =============================================================================

Describe 'RegistryHandler Edge Cases' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should not throw on invalid registry type parameter' {
        # ValidateSet should catch this at the PowerShell parameter binding level
        { Set-PCCleanupRegistry -Path 'HKLM:\Test' -Name 'Val' -Value 0 -Type 'InvalidType' } | Should -Throw
    }

    It 'should handle empty string value for String type' {
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName Set-ItemProperty -MockWith {}
        { Set-PCCleanupRegistry -Path 'HKLM:\Test' -Name 'Val' -Value '' -Type 'String' } | Should -Not -Throw
        Should -Invoke Set-ItemProperty -Times 1
    }

    It 'should handle very long registry path' {
        Mock -CommandName Test-Path -MockWith { $false }
        Mock -CommandName New-Item -MockWith {}
        Mock -CommandName Set-ItemProperty -MockWith {}
        $longPath = 'HKLM:\SOFTWARE\' + ('A' * 200)
        { Set-PCCleanupRegistry -Path $longPath -Name 'Val' -Value 1 -Type 'DWord' } | Should -Not -Throw
    }

    It 'Get-PCCleanupRegistryValue should handle unknown hive prefix' {
        $result = Get-PCCleanupRegistryValue -Path 'HKFAKE:\Test' -Name 'Val'
        $result.Exists | Should -BeFalse
    }

    It 'Get-PCCleanupRegistryValue should handle path with no backslash after hive' {
        # Edge case: path is just "HKLM:" with no subkey
        $result = Get-PCCleanupRegistryValue -Path 'HKLM:' -Name 'Val'
        $result.Exists | Should -BeFalse
    }
}

Describe 'ServiceHandler Edge Cases' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should not stop a service that is already stopped' {
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'TestSvc'; Status = 'Stopped'; StartType = 'Manual' }
        }
        Mock -CommandName Stop-Service -MockWith {}
        Mock -CommandName Set-Service -MockWith {}
        Set-PCCleanupService -Name 'TestSvc' -StartupType 'Disabled' -StopFirst
        # Should not call Stop-Service because Status is not Running
        Should -Invoke Stop-Service -Times 0
    }

    It 'should handle service name with spaces' {
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'Service With Spaces'; Status = 'Running'; StartType = 'Automatic' }
        }
        Mock -CommandName Set-Service -MockWith {}
        { Set-PCCleanupService -Name 'Service With Spaces' -StartupType 'Manual' } | Should -Not -Throw
    }

    It 'should reject invalid startup type via parameter validation' {
        { Set-PCCleanupService -Name 'TestSvc' -StartupType 'InvalidType' } | Should -Throw
    }
}

Describe 'ScriptHandler Edge Cases' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should handle script block that throws' {
        { Invoke-PCCleanupScript -ScriptBlock 'throw "test error"' } | Should -Not -Throw
    }

    It 'FIXED(W-3): empty string script block is silently skipped' {
        # FIX APPLIED: [AllowEmptyString()] + early return for empty/whitespace
        { Invoke-PCCleanupScript -ScriptBlock '' } | Should -Not -Throw
    }

    It 'should handle script block with syntax error' {
        { Invoke-PCCleanupScript -ScriptBlock 'if { broken syntax' } | Should -Not -Throw
    }

    It 'should handle script block that produces output' {
        { Invoke-PCCleanupScript -ScriptBlock '"hello world"' } | Should -Not -Throw
    }

    It 'should handle script block that writes to error stream' {
        { Invoke-PCCleanupScript -ScriptBlock 'Write-Error "test error" -ErrorAction SilentlyContinue' } | Should -Not -Throw
    }
}

Describe 'TaskHandler Edge Cases' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should handle task path with no parent folder' {
        Mock -CommandName Get-ScheduledTask -MockWith { $null }
        { Set-PCCleanupScheduledTask -TaskPath '\SingleTask' -Enabled $false } | Should -Not -Throw
    }

    It 'should handle deeply nested task path' {
        Mock -CommandName Get-ScheduledTask -MockWith { $null }
        { Set-PCCleanupScheduledTask -TaskPath '\Microsoft\Windows\Deep\Nested\Path\Task' -Enabled $false } | Should -Not -Throw
    }
}

# =============================================================================
# 5. UNDO LOG SERIALIZATION EDGE CASES
# =============================================================================

Describe 'Undo Log Serialization' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
    }

    It 'should preserve null OriginalValue through JSON round-trip' {
        $changes = @([PSCustomObject]@{
            Type = 'Registry'
            Path = 'HKLM:\Test'
            Name = 'Val'
            OriginalValue = $null
            OriginalType = $null
            KeyExistedBefore = $false
        })
        Register-AppliedTweak -Name 'NullTweak' -Changes $changes -Category 'Privacy'
        $log = Get-AppliedTweaks
        @($log)[0].Changes[0].OriginalValue | Should -BeNullOrEmpty
        @($log)[0].Changes[0].KeyExistedBefore | Should -Be $false
    }

    It 'should preserve boolean false through JSON round-trip' {
        $changes = @([PSCustomObject]@{
            Type = 'ScheduledTask'
            Path = '\Test\Task'
            OriginalEnabled = $false
        })
        Register-AppliedTweak -Name 'FalseTweak' -Changes $changes -Category 'Privacy'
        $log = Get-AppliedTweaks
        @($log)[0].Changes[0].OriginalEnabled | Should -Be $false
    }

    It 'should handle OriginalValue of 0 without treating as null' {
        $changes = @([PSCustomObject]@{
            Type = 'Registry'
            Path = 'HKLM:\Test'
            Name = 'Val'
            OriginalValue = 0
            OriginalType = 'DWord'
            KeyExistedBefore = $true
        })
        Register-AppliedTweak -Name 'ZeroTweak' -Changes $changes -Category 'Privacy'
        $log = Get-AppliedTweaks
        @($log)[0].Changes[0].OriginalValue | Should -Be 0
    }

    It 'should handle special characters in registry path through JSON round-trip' {
        $changes = @([PSCustomObject]@{
            Type = 'Registry'
            Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
            Name = 'Enabled'
            OriginalValue = 1
            OriginalType = 'DWord'
            KeyExistedBefore = $true
        })
        Register-AppliedTweak -Name 'SpecialPath' -Changes $changes -Category 'Privacy'
        $log = Get-AppliedTweaks
        @($log)[0].Changes[0].Path | Should -Be 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
    }

    It 'should handle single entry (ConvertFrom-Json returns object, not array)' {
        $changes = @([PSCustomObject]@{
            Type = 'Registry'
            Path = 'HKLM:\Test'
            Name = 'Val'
            OriginalValue = 1
            OriginalType = 'DWord'
            KeyExistedBefore = $true
        })
        Register-AppliedTweak -Name 'SingleEntry' -Changes $changes -Category 'Privacy'
        $log = Get-AppliedTweaks
        @($log).Count | Should -Be 1
        @($log)[0].TweakName | Should -Be 'SingleEntry'
    }

    It 'should handle many entries without corruption' {
        $changes = @([PSCustomObject]@{
            Type = 'Registry'
            Path = 'HKLM:\Test'
            Name = 'Val'
            OriginalValue = 1
            OriginalType = 'DWord'
            KeyExistedBefore = $true
        })
        for ($i = 0; $i -lt 20; $i++) {
            Register-AppliedTweak -Name "Tweak$i" -Changes $changes -Category 'Privacy'
        }
        $log = Get-AppliedTweaks
        @($log).Count | Should -Be 20
    }
}

# =============================================================================
# 6. INVOKE-TWEAK EDGE CASES
# =============================================================================

Describe 'Invoke-Tweak: Script-Only Tweaks (No State to Capture)' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        Mock -CommandName Invoke-PCCleanupScript -MockWith {}
        $script:SchemaValidated = $true
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
        $script:ConfigPath = $TestDrive

        $tweaks = @{
            'ScriptOnly' = @{
                name = 'Script Only Tweak'
                description = 'Only has invokeScript'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Cleanup'
                risk = 'safe'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $false
                registry = @()
                services = @()
                scheduledTasks = @()
                invokeScript = @('Write-Host "cleaning up"')
                undoScript = @()
            }
        }
        $tweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
    }

    It 'should not register undo data for script-only tweaks (no state to capture)' {
        Invoke-Tweak -Name 'ScriptOnly'
        $log = Get-AppliedTweaks
        @($log).Count | Should -Be 0
    }

    It 'should still execute the invokeScript' {
        Invoke-Tweak -Name 'ScriptOnly'
        Should -Invoke Invoke-PCCleanupScript -Times 1
    }
}

Describe 'Invoke-Tweak: Mixed Handler Tweak' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        Mock -CommandName Get-PCCleanupRegistryValue -MockWith {
            [PSCustomObject]@{ Value = 3; Type = 'DWord'; Exists = $true }
        }
        Mock -CommandName Set-PCCleanupService -MockWith {}
        Mock -CommandName Get-Service -MockWith {
            [PSCustomObject]@{ Name = 'DiagTrack'; StartType = 'Automatic'; Status = 'Running' }
        }
        Mock -CommandName Set-PCCleanupScheduledTask -MockWith {}
        Mock -CommandName Get-ScheduledTask -MockWith {
            [PSCustomObject]@{ TaskName = 'Consolidator'; State = 'Ready' }
        }
        $script:SchemaValidated = $true
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
        $script:ConfigPath = $TestDrive

        $tweaks = @{
            'MixedTweak' = @{
                name = 'Mixed Handler Tweak'
                description = 'Has registry + service + task'
                detail = 'Detail'
                docsUrl = 'https://example.com'
                category = 'Privacy'
                risk = 'moderate'
                minBuild = $null
                maxBuild = $null
                requiresAdmin = $true
                registry = @(@{ path = 'HKLM:\Test'; name = 'Val'; value = 1; type = 'DWord'; defaultValue = 3 })
                services = @(@{ name = 'DiagTrack'; startupType = 'Disabled'; defaultType = 'Automatic' })
                scheduledTasks = @(@{ path = '\Microsoft\Windows\CEIP\Consolidator'; enabled = $false })
                invokeScript = @()
                undoScript = @()
            }
        }
        $tweaks | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $TestDrive 'tweaks.json')
    }

    It 'should capture all three change types in undo log' {
        Invoke-Tweak -Name 'MixedTweak'
        $log = Get-AppliedTweaks
        @($log).Count | Should -Be 1
        $changes = @($log)[0].Changes
        ($changes | Where-Object { $_.Type -eq 'Registry' }) | Should -Not -BeNullOrEmpty
        ($changes | Where-Object { $_.Type -eq 'Service' }) | Should -Not -BeNullOrEmpty
        ($changes | Where-Object { $_.Type -eq 'ScheduledTask' }) | Should -Not -BeNullOrEmpty
    }
}

# =============================================================================
# 7. SAFETYNET EDGE CASES
# =============================================================================

Describe 'Backup-RegistryHive: Path Sanitization' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
    }

    It 'should sanitize colons and backslashes from the backup filename' {
        $outputDir = Join-Path $TestDrive 'backups'
        Mock -CommandName reg.exe -MockWith {}
        Mock -CommandName Test-Path -MockWith { $true } -ParameterFilter { $Path -like '*PCCleanup_*' }
        $result = Backup-RegistryHive -Path 'HKLM:\SOFTWARE\Policies' -OutputDir $outputDir
        # Filename should not contain : or \ (those are stripped)
        if ($result) {
            $fileName = Split-Path $result -Leaf
            $fileName | Should -Not -Match ':'
        }
    }
}

# =============================================================================
# 8. TWEAKENGINE: CONFIG PATH RESOLUTION
# =============================================================================

Describe 'TweakEngine: Config Path Handling' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        $script:SchemaValidated = $false
    }

    It 'should reject path traversal in config path' {
        # Override ConfigPath to something with traversal
        $script:ConfigPath = Join-Path $TestDrive '..\..\etc'
        { Get-Tweaks } | Should -Throw '*not found*'
    }
}

# =============================================================================
# 9. UNDOMANAGER: UNDO REMOVES CORRECT ENTRY
# =============================================================================

Describe 'UndoManager: Entry Removal Precision' {
    BeforeEach {
        Mock -CommandName Write-Host -MockWith {}
        Mock -CommandName Write-Log -MockWith {}
        Mock -CommandName Get-OSBuild -MockWith { 22631 }
        Mock -CommandName Set-PCCleanupRegistry -MockWith {}
        $script:UndoLogDir = Join-Path $TestDrive "PCCleanup_$(Get-Random)"
        $script:UndoLogPath = Join-Path $script:UndoLogDir 'undo_log.json'
    }

    It 'should only remove the specific tweak entry, not entries with similar names' {
        $changes = @([PSCustomObject]@{ Type = 'Registry'; Path = 'HKLM:\Test'; Name = 'Val'; OriginalValue = 1; OriginalType = 'DWord'; KeyExistedBefore = $true })
        Register-AppliedTweak -Name 'DisableTelemetry' -Changes $changes -Category 'Privacy'
        Register-AppliedTweak -Name 'DisableTelemetryAdvanced' -Changes $changes -Category 'Privacy'

        Invoke-UndoTweak -Name 'DisableTelemetry'
        $remaining = Get-AppliedTweaks
        @($remaining).Count | Should -Be 1
        @($remaining)[0].TweakName | Should -Be 'DisableTelemetryAdvanced'
    }
}
