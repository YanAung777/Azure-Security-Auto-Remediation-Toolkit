<#
.SYNOPSIS
    Phase 0 work item 6: baseline current open Defender recommendations + Policy
    non-compliance, grouped by category and severity, before anything is automated.

.DESCRIPTION
    Deliberately reuses Get-Phase2Findings.ps1 and Build-Phase2FindingTypeMap.ps1
    rather than writing a second, slightly different finding-ingestion routine.
    You're not building this logic twice -- Phase 0 establishes the baseline,
    Phase 2 re-runs the same ingestion continuously. If you tune the Resource
    Graph query later, both benefit.

    Output:
      - Baseline_Raw_<timestamp>.csv       -- every individual finding
      - Baseline_ByCategory_<timestamp>.csv -- counts grouped by matched category / severity
      - Baseline_Summary_<timestamp>.md     -- human-readable summary for the
                                                 "reviewed by SOC + Platform Security"
                                                 exit criterion
      - Baseline_Snapshot_<timestamp>.json  -- machine-readable snapshot for trend
                                                 comparison against future baselines
#>

param(
    [string[]]$SubscriptionIds,
    [string]$ToolkitScriptsPath = "..\Azure-Security-Auto-Remediation-Toolkit-main\Auto Remediation Azure Security Recommendations",
    [string]$AutonomyMatrixPath = "..\Phase1-SafeAutoRemediation\autonomy-matrix.json",
    [string]$OutputPath = ".\baseline"
)

. (Join-Path $PSScriptRoot "..\Phase2-IntelligenceLayer\Get-Phase2Findings.ps1")
. (Join-Path $PSScriptRoot "..\Phase2-IntelligenceLayer\Build-Phase2FindingTypeMap.ps1")

if (-not (Test-Path $OutputPath)) { New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null }
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

Write-Host "=== Phase 0 Baseline Report ===" -ForegroundColor Cyan

$matrix = if (Test-Path $AutonomyMatrixPath) { Get-Content $AutonomyMatrixPath -Raw | ConvertFrom-Json } else { $null }
$findingTypeMap = if ($matrix) { Build-Phase2FindingTypeMap -ToolkitScriptsPath $ToolkitScriptsPath -Matrix $matrix } else { @{} }

Write-Host "Querying Defender assessments..." -ForegroundColor Gray
$defenderFindings = Get-Phase2DefenderFindings -SubscriptionIds $SubscriptionIds | ConvertTo-Phase2NormalizedFinding
Write-Host "Querying Policy non-compliance..." -ForegroundColor Gray
$policyFindings = Get-Phase2PolicyFindings | ConvertTo-Phase2NormalizedFinding

$allFindings = @($defenderFindings) + @($policyFindings)
$allFindings = $allFindings | ForEach-Object {
    $matched = $findingTypeMap[$_.RecommendationName]
    $_ | Add-Member -NotePropertyName "MatchedCategory" -NotePropertyValue $matched.Category -PassThru |
         Add-Member -NotePropertyName "HasPhase1Script" -NotePropertyValue ([bool]$matched) -PassThru
}

Write-Host "Total findings: $($allFindings.Count)" -ForegroundColor Yellow

# ---- Raw export ----
$rawPath = Join-Path $OutputPath "Baseline_Raw_$timestamp.csv"
$allFindings | Export-Csv -Path $rawPath -NoTypeInformation

# ---- Grouped summary ----
$byCategory = $allFindings | Group-Object -Property @{Expression={ if ($_.MatchedCategory) { $_.MatchedCategory } else { "Unmatched" } }}, Severity |
    Select-Object @{N="Category";E={$_.Values[0]}}, @{N="Severity";E={$_.Values[1]}}, Count
$categoryPath = Join-Path $OutputPath "Baseline_ByCategory_$timestamp.csv"
$byCategory | Sort-Object Category, Severity | Export-Csv -Path $categoryPath -NoTypeInformation

# ---- Snapshot for future trend comparison ----
$snapshot = [PSCustomObject]@{
    timestampUtc     = (Get-Date).ToUniversalTime().ToString("o")
    totalFindings    = $allFindings.Count
    defenderFindings = $defenderFindings.Count
    policyFindings   = $policyFindings.Count
    matchedToPhase1  = ($allFindings | Where-Object HasPhase1Script).Count
    unmatched        = ($allFindings | Where-Object { -not $_.HasPhase1Script }).Count
    byCategory       = $byCategory
}
$snapshotPath = Join-Path $OutputPath "Baseline_Snapshot_$timestamp.json"
($snapshot | ConvertTo-Json -Depth 6) | Set-Content -Path $snapshotPath

# ---- Human-readable summary ----
$topRecommendations = $allFindings | Group-Object RecommendationName | Sort-Object Count -Descending | Select-Object -First 15

$md = @()
$md += "# Phase 0 Baseline Report — $timestamp"
$md += ""
$md += "**Total open findings:** $($allFindings.Count) ($($defenderFindings.Count) Defender, $($policyFindings.Count) Policy)"
$md += ""
$md += "**Findings a Phase 1 script already exists for:** $($snapshot.matchedToPhase1) of $($allFindings.Count)"
$md += "**Findings with no Phase 1 coverage yet:** $($snapshot.unmatched) — these stay Propose/Escalate-only until the Autonomy Matrix is extended."
$md += ""
$md += "## By category / severity"
$md += ""
$md += "| Category | Severity | Count |"
$md += "|---|---|---|"
foreach ($row in ($byCategory | Sort-Object Category, Severity)) {
    $md += "| $($row.Category) | $($row.Severity) | $($row.Count) |"
}
$md += ""
$md += "## Top 15 recommendations by volume"
$md += ""
$md += "| Recommendation | Count |"
$md += "|---|---|"
foreach ($rec in $topRecommendations) {
    $md += "| $($rec.Name) | $($rec.Count) |"
}
$md += ""
$md += "## Review sign-off"
$md += ""
$md += "- [ ] Reviewed by SOC"
$md += "- [ ] Reviewed by Platform Security"
$md += "- Date reviewed: ____________"
$md += "- Notes: ____________"

$summaryPath = Join-Path $OutputPath "Baseline_Summary_$timestamp.md"
($md -join "`n") | Set-Content -Path $summaryPath

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host "Raw:       $rawPath"
Write-Host "ByCategory: $categoryPath"
Write-Host "Snapshot:  $snapshotPath"
Write-Host "Summary:   $summaryPath  <- this is the one to send to SOC + Platform Security for sign-off"
