<#
.SYNOPSIS
    Generates a single self-contained HTML SOC dashboard from the evidence the earlier phases write.

.DESCRIPTION
    Static file, no server, no external requests -- open it or drop it on a share. Re-run on a schedule.

    Metric definitions (read these before quoting a number):
      - Open findings by decision: from the latest Phase 2 evidence file.
      - Auto success rate: Phase 1 entries with decision Auto, Remediated / (Remediated + AttemptedNoChange).
      - Time to remediate: Phase 2 cluster history, firstSeen -> resolved. It is CLUSTER-level, and
        "resolved" is only noticed on the next Phase 2 run, so precision is limited to your run
        interval. Auto-remediated findings are included; so is anyone who fixed it by hand.
      - Approval turnaround: proposal created -> executed (proposals only).
      - Recurrence: clusters that were resolved and then reappeared (Phase 2), per day.
#>
param(
    [string]$Phase1EvidencePath = (Join-Path $PSScriptRoot "../Phase1-SafeAutoRemediation/evidence"),
    [string]$Phase2EvidencePath = (Join-Path $PSScriptRoot "../Phase2-IntelligenceLayer/evidence"),
    [string]$ClusterStorePath   = (Join-Path $PSScriptRoot "../Phase2-IntelligenceLayer/state/ClusterHistory.json"),
    [string]$ProposalStorePath  = (Join-Path $PSScriptRoot "state/Proposals"),
    [string]$FeedbackPath       = (Join-Path $PSScriptRoot "state/Feedback.jsonl"),
    [int]$WindowDays = 30,
    [string]$OutFile = ".\SOC-Dashboard.html"
)
Import-Module (Join-Path $PSScriptRoot "Phase3-Common.psm1") -Force
$since = (Get-Date).ToUniversalTime().AddDays(-$WindowDays)
function Enc($s) { [System.Net.WebUtility]::HtmlEncode([string]$s) }
function Median($xs) { $a = @($xs | Sort-Object); if ($a.Count -eq 0) { return $null }; $m = [math]::Floor($a.Count / 2); if ($a.Count % 2) { $a[$m] } else { ($a[$m-1] + $a[$m]) / 2 } }
function Hours($v) { if ($null -eq $v) { "n/a" } else { "$([math]::Round($v,1)) h" } }

# ---- open findings by decision (latest Phase 2 run) ----
$latest2 = Get-ChildItem $Phase2EvidencePath -Filter "Phase2_Evidence_*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$byDecision = @{ Auto = 0; Propose = 0; Escalate = 0 }; $urgent = 0; $latest2Time = "no Phase 2 run found"
if ($latest2) {
    $p2 = Get-Content $latest2.FullName -Raw | ConvertFrom-Json
    $latest2Time = $p2.timestampUtc
    foreach ($e in $p2.entries) { $byDecision[$e.decision] += [int]$e.resourceCount; if ($e.isUrgent -or ($e.hasAttackPath -and $e.decision -eq "Escalate")) { $urgent += [int]$e.resourceCount } }
}

# ---- auto success rate ----
$auto = @()
foreach ($f in (Get-ChildItem $Phase1EvidencePath -Filter "Phase1_Evidence_*.json" -ErrorAction SilentlyContinue)) {
    $pkg = Get-Content $f.FullName -Raw | ConvertFrom-Json
    if ([datetime]$pkg.timestampUtc -lt $since) { continue }
    foreach ($e in $pkg.entries) { if ($e.decision -eq "Auto" -and $e.status -in @("Remediated","AttemptedNoChange")) { $auto += [PSCustomObject]@{ Day = ([datetime]$pkg.timestampUtc).ToString("yyyy-MM-dd"); Ok = ($e.status -eq "Remediated"); Cat = $e.category } } }
}
$autoOk = ($auto | Where-Object Ok).Count
$autoRate = if ($auto.Count) { [math]::Round(100 * $autoOk / $auto.Count, 1) } else { $null }

# ---- clusters: time to remediate + recurrence ----
$ttr = @(); $recurByDay = @{}
if (Test-Path $ClusterStorePath) {
    $cs = Get-Content $ClusterStorePath -Raw | ConvertFrom-Json -AsHashtable
    foreach ($k in $cs.Keys) {
        $v = $cs[$k]; if ($v -is [string]) { continue }
        if ($v.resolvedUtc -and $v.firstSeenUtc -and [datetime]$v.resolvedUtc -ge $since) { $ttr += (New-TimeSpan -Start ([datetime]$v.firstSeenUtc) -End ([datetime]$v.resolvedUtc)).TotalHours }
        if ($v.reappearedUtc -and [datetime]$v.reappearedUtc -ge $since) { $d = ([datetime]$v.reappearedUtc).ToString("yyyy-MM-dd"); $recurByDay[$d] = 1 + [int]$recurByDay[$d] }
    }
}

# ---- proposals + feedback ----
$props = @(Get-Phase3Proposal -ProposalStorePath $ProposalStorePath | Where-Object { [datetime]$_.createdUtc -ge $since })
$byStatus = $props | Group-Object status | Sort-Object Name
$turn = @($props | Where-Object { $_.status -eq "Executed" -and $_.execution.atUtc } | ForEach-Object { (New-TimeSpan -Start ([datetime]$_.createdUtc) -End ([datetime]$_.execution.atUtc)).TotalHours })
$fb = @(); if (Test-Path $FeedbackPath) { $fb = @(Get-Content $FeedbackPath | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { [datetime]$_.atUtc -ge $since }) }
$decided = @($props | Where-Object { $_.status -in @("Approved","Executed","Rejected","Stale","Failed") }).Count
$rej = @($props | Where-Object { $_.status -eq "Rejected" }).Count
$rejRate = if ($decided) { [math]::Round(100 * $rej / $decided, 1) } else { $null }
$reasons = $fb | Where-Object { $_.action -eq "Rejected" } | Group-Object reasonCode | Sort-Object Count -Descending

function Card($label, $value, $sub) { "<div class='card'><div class='v'>$(Enc $value)</div><div class='l'>$(Enc $label)</div><div class='s'>$(Enc $sub)</div></div>" }
function Bar($label, $n, $max, $cls) { $w = if ($max) { [math]::Round(100 * $n / $max) } else { 0 }; "<div class='row'><span class='k'>$(Enc $label)</span><span class='bar'><i class='$cls' style='width:$w%'></i></span><span class='n'>$n</span></div>" }
$maxDec = ($byDecision.Values | Measure-Object -Maximum).Maximum
$recurDays = $recurByDay.Keys | Sort-Object; $maxRec = ($recurByDay.Values | Measure-Object -Maximum).Maximum

$html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Remediation SOC Dashboard</title>
<style>
:root{--bg:#fff;--fg:#1a1a1a;--mut:#666;--card:#f5f5f4;--line:#ddd;--a:#2e7d32;--p:#b26a00;--e:#c62828;--b:#3a6ea5}
@media(prefers-color-scheme:dark){:root{--bg:#161616;--fg:#eee;--mut:#9a9a9a;--card:#222;--line:#333;--a:#66bb6a;--p:#ffb74d;--e:#ef5350;--b:#6ea8e0}}
body{margin:0;padding:20px;background:var(--bg);color:var(--fg);font:15px/1.45 system-ui,sans-serif;max-width:980px;margin-inline:auto}
h1{font-size:20px;margin:0 0 4px}h2{font-size:16px;margin:28px 0 8px}.meta{color:var(--mut);font-size:13px}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px;margin-top:16px}
.card{background:var(--card);border-radius:10px;padding:12px}.v{font-size:26px;font-weight:600}.l{font-size:13px}.s{font-size:12px;color:var(--mut);margin-top:2px}
.row{display:flex;align-items:center;gap:10px;margin:5px 0}.k{width:130px;font-size:13px}.n{width:48px;text-align:right;font-size:13px}
.bar{flex:1;background:var(--card);border-radius:4px;height:14px;overflow:hidden}.bar i{display:block;height:100%}
.Auto{background:var(--a)}.Propose{background:var(--p)}.Escalate{background:var(--e)}.rec{background:var(--b)}
table{border-collapse:collapse;width:100%;font-size:13px}td,th{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line)}
.note{font-size:12px;color:var(--mut);margin-top:6px}
</style></head><body>
<h1>Remediation SOC Dashboard</h1>
<div class="meta">Window: last $WindowDays days &middot; generated $(Get-Date -Format "yyyy-MM-dd HH:mm") &middot; latest Phase 2 run: $(Enc $latest2Time)</div>
<div class="cards">
$(Card "Auto success rate" $(if ($null -ne $autoRate) { "$autoRate%" } else { "n/a" }) "$autoOk of $($auto.Count) auto actions")
$(Card "Median time to remediate" (Hours (Median $ttr)) "$($ttr.Count) resolved clusters")
$(Card "Approval turnaround" (Hours (Median $turn)) "median, $($turn.Count) executed proposals")
$(Card "Rejection rate" $(if ($null -ne $rejRate) { "$rejRate%" } else { "n/a" }) "$rej of $decided decided proposals")
$(Card "On attack paths / urgent" $urgent "resources in latest run")
</div>
<h2>Open findings by decision (resources)</h2>
$(Bar "Auto" $byDecision.Auto $maxDec "Auto")
$(Bar "Propose" $byDecision.Propose $maxDec "Propose")
$(Bar "Escalate" $byDecision.Escalate $maxDec "Escalate")
<div class="note">Auto here means "eligible for auto-remediation under the matrix", not "already fixed".</div>
<h2>Approval pipeline</h2>
<table><tr><th>Status</th><th>Proposals</th></tr>
$(if ($byStatus) { ($byStatus | ForEach-Object { "<tr><td>$(Enc $_.Name)</td><td>$($_.Count)</td></tr>" }) -join "" } else { "<tr><td colspan='2'>No proposals in window</td></tr>" })
</table>
<h2>Why humans rejected proposals</h2>
<table><tr><th>Reason</th><th>Count</th></tr>
$(if ($reasons) { ($reasons | ForEach-Object { "<tr><td>$(Enc $_.Name)</td><td>$($_.Count)</td></tr>" }) -join "" } else { "<tr><td colspan='2'>No rejections in window</td></tr>" })
</table>
<h2>Recurrence (fixed, then came back)</h2>
$(if ($recurDays) { ($recurDays | ForEach-Object { Bar $_ $recurByDay[$_] $maxRec "rec" }) -join "" } else { "<div class='note'>No recurrences recorded in window.</div>" })
<div class="note">Time-to-remediate is cluster-level and only observed at Phase 2 run cadence; it includes fixes made by people as well as automation.</div>
</body></html>
"@
$html | Set-Content -Path $OutFile -Encoding UTF8
Write-Host "Wrote $OutFile" -ForegroundColor Green
