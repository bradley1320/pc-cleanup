# ==============================================================================
# PC Cleanup v2 -- CI stage runner
#
# GitHub Actions does not allow expressions in a step's "shell:" key, and
# jobs.<job_id>.defaults.run.shell forbids contexts outright, so a matrix cannot
# select the shell. CI therefore needs one job per runtime with the shell
# hardcoded. Putting the actual work here keeps those jobs to one-liners so the
# two legs cannot drift apart, and lets the same checks be run locally:
#
#     .\build\ci\Invoke-CIStage.ps1 -Stage Lint
#
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Install', 'Lint', 'Test', 'Build', 'VerifyConfig', 'VerifyAscii', 'VerifyDist')]
    [string]$Stage
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Push-Location $repoRoot
try {
    Write-Host "== $Stage == PowerShell $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" -ForegroundColor Cyan

    switch ($Stage) {

        'Install' {
            # Windows PowerShell 5.1 defaults to TLS 1.0/1.1 and ships without the
            # NuGet provider, so it cannot reach the PSGallery until both are set up.
            # PowerShell 7 already has them; these calls are harmless there.
            [Net.ServicePointManager]::SecurityProtocol =
                [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

            try { Get-PackageProvider -Name NuGet -ForceBootstrap -ErrorAction Stop | Out-Null }
            catch { Write-Host "NuGet provider bootstrap skipped: $($_.Exception.Message)" }

            try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop }
            catch { Write-Host "PSGallery trust not set: $($_.Exception.Message)" }

            Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser -AllowClobber

            # Pin to 5.x. -MinimumVersion on its own installs whatever is newest,
            # which silently became Pester 6 -- and Pester 6 throws on an unmatched
            # mock instead of falling through, which this suite relies on.
            #
            # -SkipPublisherCheck is required on 5.1: Windows ships a
            # Microsoft-signed Pester 3.4.0 in Program Files, and a gallery-signed
            # build will not install alongside it without this.
            Install-Module -Name Pester -Force -Scope CurrentUser -SkipPublisherCheck -MinimumVersion 5.0.0 -MaximumVersion 5.99.99

            $pester = Get-Module Pester -ListAvailable |
                Where-Object { $_.Version -ge [version]'5.0.0' -and $_.Version -lt [version]'6.0.0' } |
                Sort-Object Version -Descending | Select-Object -First 1
            if (-not $pester) { throw 'No Pester 5.x available after install.' }
            Write-Host "Pester $($pester.Version) at $($pester.ModuleBase)"
        }

        'Lint' {
            $results = Invoke-ScriptAnalyzer -Path src/ -Recurse -Severity Warning, Error -Settings .psscriptanalyzerrc.psd1
            if ($results) {
                $results | Format-Table -AutoSize
                throw "PSScriptAnalyzer found $($results.Count) issue(s)."
            }
            Write-Host 'PSScriptAnalyzer: all clear.' -ForegroundColor Green
        }

        'Test' {
            # Explicit, version-bounded import. Without it, 5.1 loads the shipped
            # Pester 3.4.0 (which has no New-PesterConfiguration) and a hosted
            # runner could load Pester 6.
            Import-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99
            Write-Host "Pester $((Get-Module Pester).Version)"

            $config = New-PesterConfiguration
            $config.Run.Path = 'tests/unit'
            $config.Run.Exit = $true
            $config.Output.Verbosity = 'Detailed'
            $config.TestResult.Enabled = $true
            $config.TestResult.OutputPath = 'test-results.xml'
            Invoke-Pester -Configuration $config
        }

        'Build' {
            & build/Build.ps1 -Package
            if (-not (Test-Path dist/pccleanup.ps1)) {
                throw 'Build.ps1 did not produce dist/pccleanup.ps1'
            }
            $lineCount = (Get-Content dist/pccleanup.ps1).Count
            Write-Host "Build produced $lineCount lines." -ForegroundColor Green
        }

        'VerifyConfig' {
            foreach ($cfg in @('tweaks.json', 'apps-bloat.json', 'apps-critical.json', 'profiles.json')) {
                if (-not (Test-Path "dist/config/$cfg")) {
                    throw "Build did not copy $cfg to dist/config/"
                }
            }
            Write-Host 'All config files present in dist/.' -ForegroundColor Green
        }

        'VerifyAscii' {
            # PowerShell 5.1 reads .ps1 as ANSI, not UTF-8, so a stray em dash or
            # arrow becomes mojibake that can break the parser on a user's machine.
            # This rule was previously enforced only by hand.
            $bad = @()
            foreach ($file in (Get-ChildItem -Path src/ -Recurse -Filter '*.ps1')) {
                $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
                for ($i = 0; $i -lt $bytes.Length; $i++) {
                    if ($bytes[$i] -gt 127) {
                        $bad += ('{0} at byte {1} (0x{2:X2})' -f $file.FullName, $i, $bytes[$i])
                        break
                    }
                }
            }
            if ($bad) {
                $bad | ForEach-Object { Write-Host $_ }
                throw "Found non-ASCII bytes in $($bad.Count) source file(s)."
            }
            Write-Host 'Source is pure ASCII.' -ForegroundColor Green
        }

        'VerifyDist' {
            # dist/pccleanup.ps1 is produced by text surgery on src/ -- the param
            # block is hoisted, DIST_EXCLUDE regions are dropped and config hashes
            # are spliced in -- so a clean src/ does not prove a runnable build.
            # These checks run against the artifact users actually download.
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Resolve-Path dist/pccleanup.ps1).Path, [ref]$tokens, [ref]$parseErrors)
            if ($parseErrors) {
                $parseErrors | ForEach-Object { Write-Host "  line $($_.Extent.StartLineNumber): $($_.Message)" }
                throw "dist/pccleanup.ps1 has $($parseErrors.Count) parse error(s)."
            }

            # Concatenation lets a later definition silently replace an earlier one.
            $dupes = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) |
                Group-Object Name | Where-Object Count -gt 1
            if ($dupes) {
                throw "Functions defined more than once in dist/pccleanup.ps1: $(@($dupes.Name) -join ', ')"
            }

            # Test-ConfigIntegrity treats an empty hash table as dev mode and skips
            # the check, so if Build.ps1's splice ever stopped matching, a release
            # would ship with tamper detection silently switched off.
            foreach ($cfg in @('tweaks.json', 'apps-bloat.json', 'apps-critical.json', 'profiles.json')) {
                $hash = (Get-FileHash -Path "dist/config/$cfg" -Algorithm SHA256).Hash
                if (-not (Select-String -Path dist/pccleanup.ps1 -SimpleMatch -Pattern "'$cfg' = '$hash'" -Quiet)) {
                    throw "dist/pccleanup.ps1 does not embed the SHA-256 of dist/config/$cfg."
                }
            }

            # VerifyAscii covers src/, but the build header and the launcher ship too.
            foreach ($file in @('dist/pccleanup.ps1', 'dist/Run.bat')) {
                $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $file).Path)
                # Windows PowerShell writes a UTF-8 BOM, which helps 5.1 detect the encoding.
                $start = 0
                if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                    $start = 3
                }
                for ($i = $start; $i -lt $bytes.Length; $i++) {
                    if ($bytes[$i] -gt 127) {
                        throw ('{0} has a non-ASCII byte at offset {1} (0x{2:X2}).' -f $file, $i, $bytes[$i])
                    }
                }
            }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path dist/pc-cleanup-v2.zip).Path)
            try {
                $entries = @($zip.Entries | ForEach-Object { $_.FullName })
            }
            finally {
                $zip.Dispose()
            }
            $expected = @('pccleanup.ps1', 'Run.bat', 'config/apps-bloat.json', 'config/apps-critical.json',
                'config/profiles.json', 'config/tweaks.json')
            $diff = Compare-Object -ReferenceObject $expected -DifferenceObject $entries -CaseSensitive
            if ($diff) {
                $diff | Format-Table -AutoSize | Out-String | Write-Host
                throw 'dist/pc-cleanup-v2.zip does not hold exactly the expected entries.'
            }

            Write-Host "Compiled script parses, defines each function once, embeds config hashes and is ASCII; zip holds $($entries.Count) expected entries." -ForegroundColor Green
        }
    }
}
finally {
    Pop-Location
}
