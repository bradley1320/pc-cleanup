# ==============================================================================
# PC Cleanup v2 -- PowerShell 5.1 Single-Item Unrolling Contract Tests
#
# In PS 5.1 a function that returns a collection of exactly ONE item unrolls to
# a bare scalar at the call site. A scalar has no .Count property, so
# "$x.Count -gt 0" silently evaluates to $false and the guarded work is skipped
# with no error. This shipped as a real defect: selecting exactly one Quick Clean
# target printed "No targets selected." and cleaned nothing.
#
# ".Count -eq 0" guards are NOT affected -- $null -eq 0 is $false (one item, so
# the guard correctly falls through) and $null.Count is 0 (zero items, so the
# guard correctly fires). Only the "-gt 0" shape is unsafe.
#
# These are source-contract tests, matching the existing pattern in
# CLIParsing.Tests.ps1 and FullTuneUp.Tests.ps1.
# ==============================================================================

Describe 'PS 5.1 unrolling: language behaviour' {
    It 'confirms a one-item return unrolls and loses .Count' {
        function Test-ReturnsOne { return @([PSCustomObject]@{ N = 1 }) }
        $unwrapped = Test-ReturnsOne
        $wrapped = @(Test-ReturnsOne)

        # This is the trap: .Count is $null, so the guard is $false.
        ($unwrapped.Count -gt 0) | Should -BeFalse
        ($wrapped.Count -gt 0) | Should -BeTrue
        $wrapped.Count | Should -Be 1
    }

    It 'confirms a zero-item return still reports .Count of 0' {
        function Test-ReturnsNone { return @() }
        $unwrapped = Test-ReturnsNone
        # $null.Count is 0 in PS 5.1, which is why "-eq 0" guards are safe.
        $unwrapped.Count | Should -Be 0
    }
}

Describe 'PS 5.1 unrolling: source contract' {
    It 'every ".Count -gt 0" guard is fed by an @()-wrapped assignment' {
        $sources = @(
            "$PSScriptRoot/../../src/ui/Menu.ps1"
            "$PSScriptRoot/../../src/main.ps1"
            "$PSScriptRoot/../../src/modules/QuickClean.ps1"
            "$PSScriptRoot/../../src/modules/StartupManager.ps1"
            "$PSScriptRoot/../../src/modules/PrivacyShield.ps1"
            "$PSScriptRoot/../../src/modules/PerformanceMode.ps1"
        )

        $violations = @()
        foreach ($src in $sources) {
            if (-not (Test-Path $src)) { continue }
            $name = Split-Path $src -Leaf
            $lines = @(Get-Content -Path $src)

            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -notmatch '\$(\w+)\.Count\s+-gt\s+0') { continue }
                $varName = $Matches[1]

                # Walk back to the nearest assignment of that variable.
                for ($j = $i - 1; ($j -ge 0) -and ($j -ge $i - 30); $j--) {
                    if ($lines[$j] -match ('\$' + [regex]::Escape($varName) + '\s*=\s*(\S.*)$')) {
                        $rhs = $Matches[1].Trim()
                        # Only a bare Verb-Noun call is dangerous. Literals,
                        # @()-wrapped calls, and sub-expressions are all fine.
                        if (($rhs -match '^[A-Z][a-zA-Z]*-[A-Za-z]+') -and ($rhs -notmatch '^@\(')) {
                            $violations += ('{0}:{1} -- ${2} = {3}' -f $name, ($j + 1), $varName, $rhs)
                        }
                        break
                    }
                }
            }
        }

        # A failure here means a one-item result will silently skip the guarded work.
        ($violations -join '; ') | Should -BeNullOrEmpty
    }
}
