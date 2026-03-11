@{
    # PSScriptAnalyzer settings for PC Cleanup v2
    # Suppress rules that are by-design for this project.

    ExcludeRules = @(
        # Write-Host is intentional -- this is a CLI tool with colored console output.
        # All Write-Success/Info/Warn/Err/Skip helpers use Write-Host by design.
        'PSAvoidUsingWriteHost',

        # Source files are ASCII-only (no non-ASCII characters). BOM is unnecessary
        # for ASCII files and PS 5.1 handles them correctly without BOM.
        'PSUseBOMForUnicodeEncodedFile',

        # Plural nouns are intentional for functions that return collections:
        # Get-Tweaks, Get-AppliedTweaks, Get-CleanupTargets, Get-BrowserProfiles, etc.
        'PSUseSingularNouns',

        # Write-Log only exists in PS Core 6.1+. Our target is PS 5.1 Desktop
        # where Write-Log does not exist as a built-in cmdlet.
        'PSAvoidOverwritingBuiltInCmdlets'
    )
}
