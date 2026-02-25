# ==============================================================================
# PC Cleanup v2 -- 04-TweakEngine.ps1
# JSON-driven tweak engine: loads tweaks.json, filters by risk/OS,
# dispatches to handlers. The core of the data-driven architecture.
# ==============================================================================

# Config path -- resolved relative to core/ dir in normal usage, overridable in tests
$script:ConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config'
$script:SchemaValidated = $false

function Test-TweakSchema {
    <#
    .SYNOPSIS
        Validates tweaks.json entries against the expected schema.
    .DESCRIPTION
        Verifies required fields, valid risk values, and handler-specific fields.
        Called once on first load. Throws on invalid schema to prevent silent failures.
    .PARAMETER Tweaks
        Array of tweak objects to validate.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Tweaks
    )

    foreach ($tweak in $Tweaks) {
        $id = $tweak.Id

        # Required top-level fields
        foreach ($field in @('name', 'description', 'category', 'risk')) {
            if (-not $tweak.$field) {
                throw "tweaks.json is invalid: Tweak '$id' is missing required field '$field'. Please restore from original ZIP."
            }
        }

        # Risk must be one of the valid tiers
        if ($tweak.risk -notin @('safe', 'moderate', 'advanced')) {
            throw "tweaks.json is invalid: Tweak '$id' has invalid risk value '$($tweak.risk)'. Must be safe, moderate, or advanced."
        }

        # Validate registry entries
        if ($tweak.registry) {
            foreach ($reg in $tweak.registry) {
                foreach ($field in @('path', 'name', 'type')) {
                    if (-not $reg.$field) {
                        throw "tweaks.json is invalid: Tweak '$id' has a registry entry missing required field '$field'."
                    }
                }
                # 'value' can be 0/false which are falsy -- check for $null specifically
                if ($null -eq $reg.value) {
                    throw "tweaks.json is invalid: Tweak '$id' has a registry entry missing required field 'value'."
                }
                if ($null -eq $reg.defaultValue -and $reg.defaultValue -ne 0) {
                    # defaultValue can be 0 -- only error if truly missing (not present as property)
                    $hasDefault = $reg.PSObject.Properties.Name -contains 'defaultValue'
                    if (-not $hasDefault) {
                        throw "tweaks.json is invalid: Tweak '$id' has a registry entry missing required field 'defaultValue'."
                    }
                }
            }
        }

        # Validate service entries
        if ($tweak.services) {
            foreach ($svc in $tweak.services) {
                foreach ($field in @('name', 'startupType', 'defaultType')) {
                    if (-not $svc.$field) {
                        throw "tweaks.json is invalid: Tweak '$id' has a service entry missing required field '$field'."
                    }
                }
            }
        }

        # Validate scheduled task entries
        if ($tweak.scheduledTasks) {
            foreach ($task in $tweak.scheduledTasks) {
                if (-not $task.path) {
                    throw "tweaks.json is invalid: Tweak '$id' has a scheduledTask entry missing required field 'path'."
                }
                # 'enabled' is a boolean that can be $false -- check property existence
                $hasEnabled = $task.PSObject.Properties.Name -contains 'enabled'
                if (-not $hasEnabled) {
                    throw "tweaks.json is invalid: Tweak '$id' has a scheduledTask entry missing required field 'enabled'."
                }
            }
        }
    }
}

function Get-Tweaks {
    <#
    .SYNOPSIS
        Returns filtered tweak objects from tweaks.json.
    .DESCRIPTION
        Loads the tweak catalog, filters by category and risk level,
        and applies OS build gating (minBuild/maxBuild). Validates
        the JSON schema on first load.
    .PARAMETER Category
        Filter by tweak category (e.g. 'Privacy', 'Performance', 'Cleanup').
    .PARAMETER RiskLevel
        Maximum risk level to include ('safe', 'moderate', 'advanced').
        'safe' returns only safe tweaks. 'moderate' includes safe + moderate.
        'advanced' includes all.
    .OUTPUTS
        [PSCustomObject[]] Array of tweak objects matching the filters.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Params used in Where-Object filters and switch')]
    [CmdletBinding()]
    param(
        [string]$Category,

        [ValidateSet('safe', 'moderate', 'advanced')]
        [string]$RiskLevel = 'safe'
    )

    $tweaksPath = Join-Path $script:ConfigPath 'tweaks.json'
    if (-not (Test-Path $tweaksPath)) {
        throw "tweaks.json not found at '$tweaksPath'. Please restore from original ZIP."
    }

    $raw = Get-Content -Path $tweaksPath -Raw | ConvertFrom-Json

    # Convert PSCustomObject to array of tweaks, adding the key as Id
    $tweaks = @()
    foreach ($prop in $raw.PSObject.Properties) {
        # Skip metadata keys (starting with _)
        if ($prop.Name.StartsWith('_')) { continue }

        $tweak = $prop.Value
        $tweak | Add-Member -NotePropertyName 'Id' -NotePropertyValue $prop.Name -Force
        $tweaks += $tweak
    }

    # Schema validation on first load (skip for empty catalogs)
    if (-not $script:SchemaValidated) {
        if ($tweaks.Count -gt 0) {
            Test-TweakSchema -Tweaks $tweaks
        }
        $script:SchemaValidated = $true
    }

    # Filter by category
    if ($Category) {
        $tweaks = @($tweaks | Where-Object { $_.category -eq $Category })
    }

    # Filter by risk level -- cumulative: safe < moderate < advanced
    $allowedRisks = switch ($RiskLevel) {
        'safe'     { @('safe') }
        'moderate' { @('safe', 'moderate') }
        'advanced' { @('safe', 'moderate', 'advanced') }
    }
    $tweaks = @($tweaks | Where-Object { $_.risk -in $allowedRisks })

    # OS build gating
    $currentBuild = Get-OSBuild
    $filtered = @()
    foreach ($tweak in $tweaks) {
        if ($tweak.minBuild -and $currentBuild -lt $tweak.minBuild) {
            Write-Skip "Skipping '$($tweak.name)' -- requires build $($tweak.minBuild)+, current build is $currentBuild."
            continue
        }
        if ($tweak.maxBuild -and $currentBuild -gt $tweak.maxBuild) {
            Write-Skip "Skipping '$($tweak.name)' -- only supported on build $($tweak.maxBuild) or earlier, current build is $currentBuild."
            continue
        }
        $filtered += $tweak
    }

    return $filtered
}

function Invoke-Tweak {
    <#
    .SYNOPSIS
        Applies or undoes a single tweak by name.
    .DESCRIPTION
        Dispatches to the appropriate handlers (Registry, Service, Task, Script)
        based on the tweak definition. On apply: captures current state via
        handlers, stores in UndoManager, then applies target values. On undo:
        reads original values from undo_log.json and restores them.
    .PARAMETER Name
        The TweakID from tweaks.json.
    .PARAMETER Undo
        If specified, undoes the tweak instead of applying it.
    .EXAMPLE
        Invoke-Tweak -Name 'DisableAdvertisingID'
        Invoke-Tweak -Name 'DisableAdvertisingID' -Undo
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Params used in expressions and cmdlet calls')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [switch]$Undo
    )

    if ($Undo) {
        Invoke-UndoTweak -Name $Name
        return
    }

    # Idempotency guard -- skip if tweak is already applied (in undo log)
    $appliedTweaks = Get-AppliedTweaks
    $alreadyApplied = @($appliedTweaks | Where-Object { $_.TweakName -eq $Name })
    if ($alreadyApplied.Count -gt 0) {
        Write-Info "'$Name' is already applied. Undo it first before re-applying."
        return
    }

    # Load the specific tweak (unfiltered by risk/build -- caller already gated)
    $tweaksPath = Join-Path $script:ConfigPath 'tweaks.json'
    $raw = Get-Content -Path $tweaksPath -Raw | ConvertFrom-Json
    $tweak = $raw.$Name

    if ($null -eq $tweak) {
        Write-Warn "Tweak '$Name' not found in tweaks.json."
        return
    }

    Write-Info "Applying: $($tweak.name)..."
    $allChanges = @()

    # Capture original state and build change records
    # Registry entries
    if ($tweak.registry -and $tweak.registry.Count -gt 0) {
        foreach ($reg in $tweak.registry) {
            $current = Get-PCCleanupRegistryValue -Path $reg.path -Name $reg.name
            $allChanges += [PSCustomObject]@{
                Type             = 'Registry'
                Path             = $reg.path
                Name             = $reg.name
                OriginalValue    = $current.Value
                OriginalType     = $current.Type
                KeyExistedBefore = $current.Exists
            }
        }
    }

    # Services
    if ($tweak.services -and $tweak.services.Count -gt 0) {
        foreach ($svc in $tweak.services) {
            $current = Get-Service -Name $svc.name -ErrorAction SilentlyContinue
            if ($current) {
                $allChanges += [PSCustomObject]@{
                    Type                = 'Service'
                    Name                = $svc.name
                    OriginalStartupType = $current.StartType.ToString()
                    OriginalStatus      = $current.Status.ToString()
                }
            }
        }
    }

    # Scheduled tasks
    if ($tweak.scheduledTasks -and $tweak.scheduledTasks.Count -gt 0) {
        foreach ($task in $tweak.scheduledTasks) {
            $folder = Split-Path $task.path -Parent
            $taskName = Split-Path $task.path -Leaf
            if (-not $folder.EndsWith('\')) { $folder = "$folder\" }
            $current = Get-ScheduledTask -TaskPath $folder -TaskName $taskName -ErrorAction SilentlyContinue
            if ($current) {
                $allChanges += [PSCustomObject]@{
                    Type            = 'ScheduledTask'
                    Path            = $task.path
                    OriginalEnabled = ($current.State -ne 'Disabled')
                }
            }
        }
    }

    # Register with UndoManager before applying (skip for script-only tweaks with no state to capture)
    if ($allChanges.Count -gt 0) {
        Register-AppliedTweak -Name $Name -Changes $allChanges -Category $tweak.category
    }

    # Apply target values
    # Registry
    if ($tweak.registry -and $tweak.registry.Count -gt 0) {
        foreach ($reg in $tweak.registry) {
            Set-PCCleanupRegistry -Path $reg.path -Name $reg.name -Value $reg.value -Type $reg.type
        }
    }

    # Services
    if ($tweak.services -and $tweak.services.Count -gt 0) {
        foreach ($svc in $tweak.services) {
            $stopFirst = $svc.startupType -eq 'Disabled'
            Set-PCCleanupService -Name $svc.name -StartupType $svc.startupType -StopFirst:$stopFirst
        }
    }

    # Scheduled tasks
    if ($tweak.scheduledTasks -and $tweak.scheduledTasks.Count -gt 0) {
        foreach ($task in $tweak.scheduledTasks) {
            Set-PCCleanupScheduledTask -TaskPath $task.path -Enabled $task.enabled
        }
    }

    # Invoke scripts
    if ($tweak.invokeScript -and $tweak.invokeScript.Count -gt 0) {
        foreach ($script in $tweak.invokeScript) {
            Invoke-PCCleanupScript -ScriptBlock $script
        }
    }

    Write-Success "Applied: $($tweak.name)"
}

function Invoke-TweakSet {
    <#
    .SYNOPSIS
        Applies or undoes all tweaks in a category at a given risk level.
    .DESCRIPTION
        Convenience function that calls Invoke-Tweak for each matching tweak.
        Respects risk tier and OS build gating.
    .PARAMETER Category
        The tweak category to target.
    .PARAMETER RiskLevel
        Maximum risk level to include.
    .PARAMETER Undo
        If specified, undoes the tweaks instead of applying them.
    .EXAMPLE
        Invoke-TweakSet -Category 'Privacy' -RiskLevel 'safe'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Category,

        [ValidateSet('safe', 'moderate', 'advanced')]
        [string]$RiskLevel = 'safe',

        [switch]$Undo
    )

    $tweaks = Get-Tweaks -Category $Category -RiskLevel $RiskLevel
    if ($tweaks.Count -eq 0) {
        Write-Info "No tweaks found for category '$Category' at risk level '$RiskLevel'."
        return
    }

    Write-Info "Processing $($tweaks.Count) tweak(s) in '$Category' ($RiskLevel)..."

    foreach ($tweak in $tweaks) {
        Invoke-Tweak -Name $tweak.Id -Undo:$Undo
    }
}
