<#
.SYNOPSIS
    Builds a map of {Defender recommendation display name -> Phase 1 category + script}
    by reading the .SYNOPSIS block already present in each Fix-*.ps1 file, e.g.:

        .SYNOPSIS
            Auto-fix: "Storage accounts should have the specified minimum TLS version"

    This is deliberately NOT a hand-maintained lookup table. The toolkit scripts already
    state which recommendation they fix, in their own header comment -- reading it here
    means the map can never drift out of sync with the scripts themselves. If a script's
    SYNOPSIS changes, this map picks it up automatically on the next run.

    Only scripts listed in the autonomy matrix's "scripts" arrays are considered, i.e.
    only Phase 1's four in-scope categories. Everything else in the toolkit (Identity,
    SQL, Networking, ...) is intentionally out of scope until later phases extend the
    Autonomy Matrix -- see phase2-config.json / autonomy-matrix.json.
#>

function Build-Phase2FindingTypeMap {
    param(
        [Parameter(Mandatory)] [string]$ToolkitScriptsPath,
        [Parameter(Mandatory)] $Matrix
    )

    $map = @{}
    $unparsed = @()

    foreach ($catName in $Matrix.categories.PSObject.Properties.Name) {
        $cat = $Matrix.categories.$catName
        foreach ($scriptName in $cat.scripts) {
            $scriptPath = Join-Path $ToolkitScriptsPath $scriptName
            if (-not (Test-Path $scriptPath)) {
                $unparsed += "$scriptName (file not found at $scriptPath)"
                continue
            }
            $content = Get-Content $scriptPath -Raw
            if ($content -match '(?s)\.SYNOPSIS\s*.*?Auto-fix:\s*"([^"]+)"') {
                $displayName = $Matches[1].Trim()
                $map[$displayName] = [PSCustomObject]@{
                    Category = $catName
                    Script   = $scriptName
                }
            } else {
                $unparsed += "$scriptName (no 'Auto-fix: \"...\"' pattern found in SYNOPSIS)"
            }
        }
    }

    if ($unparsed.Count -gt 0) {
        Write-Warning "Build-Phase2FindingTypeMap: could not derive a recommendation name for: $($unparsed -join '; '). These scripts' findings will be treated as unmatched (visibility-only) until this is fixed."
    }

    return $map
}
