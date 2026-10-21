<#
.SYNOPSIS
    Evidence check for expanding the Autonomy Matrix. Reports; never edits the matrix.

.DESCRIPTION
    "Add categories that have proven safe" needs a definition of proven. Defaults (phase3-config.json):
    in the last 30 days, at least 20 successful actions, >=98% success, zero human rejections, zero
    recurrences (a fixed resource coming back non-compliant means something is un-fixing it).
    Evidence only counts for the environment tier it was gathered in: successes in NonProd say
    nothing about ProdHighRisk. A passing check means "worth a change-control review", not "promote".
#>
param(
    [string]$EvidencePath = (Join-Path $PSScriptRoot "../Phase1-SafeAutoRemediation/evidence"),
    [string]$FeedbackPath = (Join-Path $PSScriptRoot "state/Feedback.jsonl"),
    [string]$OutFile = ".\PromotionReport_$(Get-Date -Format 'yyyyMMdd').md"
)
Import-Module (Join-Path $PSScriptRoot "Phase3-Common.psm1") -Force
$c = (Get-Phase3Config).promotionCriteria
$since = (Get-Date).ToUniversalTime().AddDays(-$c.windowDays)

$rows = @()
foreach ($f in (Get-ChildItem $EvidencePath -Filter "Phase1_Evidence_*.json" -ErrorAction SilentlyContinue)) {
    $pkg = Get-Content $f.FullName -Raw | ConvertFrom-Json
    if ([datetime]$pkg.timestampUtc -lt $since) { continue }
    foreach ($e in $pkg.entries) { if ($e.status -in @("Remediated","AttemptedNoChange")) { $rows += [PSCustomObject]@{ Category = $e.category; Environment = $pkg.environment; Ok = ($e.status -eq "Remediated"); Recurring = [bool]$e.isRecurring } } }
}
$rejections = @()
if (Test-Path $FeedbackPath) { $rejections = Get-Content $FeedbackPath | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.action -eq "Rejected" -and [datetime]$_.atUtc -ge $since } }

$md = @("# Autonomy promotion evidence — last $($c.windowDays) days", "",
        "Thresholds: >= $($c.minActions) actions, >= $([math]::Round($c.minSuccessRate*100))% success, <= $($c.maxRejections) rejections, <= $($c.maxRecurrences) recurrences. A pass means *eligible for review*, not promoted.", "",
        "| Category | Evidence tier | Actions | Success | Rejections | Recurrences | Verdict |", "|---|---|---|---|---|---|---|")
$groups = $rows | Group-Object Category, Environment
if (-not $groups) { $md += "| (none) | | 0 | | | | No evidence in window — nothing to assess yet |" }
foreach ($g in $groups) {
    $cat, $envName = $g.Group[0].Category, $g.Group[0].Environment
    $n = $g.Count; $ok = ($g.Group | Where-Object Ok).Count; $rate = if ($n) { $ok / $n } else { 0 }
    $rej = @($rejections | Where-Object { $_.category -eq $cat -and $_.environment -eq $envName }).Count
    $rec = ($g.Group | Where-Object Recurring).Count
    $why = @()
    if ($n -lt $c.minActions) { $why += "only $n actions" }
    if ($rate -lt $c.minSuccessRate) { $why += "success $([math]::Round($rate*100,1))%" }
    if ($rej -gt $c.maxRejections) { $why += "$rej rejection(s)" }
    if ($rec -gt $c.maxRecurrences) { $why += "$rec recurrence(s)" }
    $verdict = if ($why.Count) { "Not yet: " + ($why -join "; ") } else { "Eligible for change-control review (evidence is for $envName only)" }
    $md += "| $cat | $envName | $n | $([math]::Round($rate*100,1))% | $rej | $rec | $verdict |"
}
$md | Set-Content $OutFile
$md | ForEach-Object { Write-Host $_ }
Write-Host "`nSaved $OutFile" -ForegroundColor Green
