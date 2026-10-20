<#
.SYNOPSIS
    Phase 2 - Intelligence Layer orchestrator.

.DESCRIPTION
    1. Ingests Defender assessments + Policy non-compliance, normalizes to one schema.
    2. Clusters findings by RecommendationName + Subscription + ResourceGroup.
    3. Enriches each cluster with environment, an Owner-tag sample, and attack-path presence.
    4. Scores priority with a simple, transparent weighted rule (see phase2-config.json).
    5. Decides Auto / Propose / Escalate per cluster:
         - Matched findings (a Phase 1 script exists for them) use the Autonomy Matrix.
         - Unmatched findings (nothing can execute them yet) are always Propose/Escalate --
           never Auto, because there is no execution capability to call.
         - Attack-path presence can only ever move a decision toward MORE human
           attention (Propose -> Escalate), never toward more autonomy.
    6. For matched clusters that resolve to Auto, calls Invoke-Phase1AutoRemediation.ps1
       for that category -- this script does not re-implement remediation, tagging, or
       evidence capture. Phase 1 remains the only thing that touches Azure resources.
    7. Writes a Phase 2 evidence file and sends Teams notifications (per user's Phase 2
       decision: no ITSM integration yet).

.NOTES
    Deferred / not in this build:
      - CMDB/Service Catalog ownership lookup (Owner tag only, best-effort, first
        resource in the cluster -- not per-resource).
      - Event-driven triggering (Event Grid/Logic App). This is a script you run on a
        schedule; wiring a "new Critical recommendation" trigger is a later exercise.
      - Real ITSM ticket creation (Teams-only per your answer). If that changes,
        replace Send-Phase2TeamsNotification's Escalate/Propose branch.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$SubscriptionIds,

    [string]$ToolkitScriptsPath = "..\Azure-Security-Auto-Remediation-Toolkit-main\Auto Remediation Azure Security Recommendations",
    [string]$AutonomyMatrixPath = "..\Phase1-SafeAutoRemediation\autonomy-matrix.json",
    [string]$Phase1OrchestratorPath = "..\Phase1-SafeAutoRemediation\Invoke-Phase1AutoRemediation.ps1",
    [string]$Phase1EvidencePath = "..\Phase1-SafeAutoRemediation\evidence",
    [string]$Phase2ConfigPath = ".\phase2-config.json",

    [string]$EvidenceOutputPath = ".\evidence",
    [string]$ClusterStorePath = ".\state\ClusterHistory.json",
    [string]$LogPath = ".\logs",
    [string]$KillSwitchPath = "..\Phase1-SafeAutoRemediation\PAUSE_AUTOREMEDIATION",

    [string]$TeamsWebhookUrl,
    [switch]$ForcePropose
)

#region ====================== SETUP ======================
. (Join-Path $PSScriptRoot "Build-Phase2FindingTypeMap.ps1")
. (Join-Path $PSScriptRoot "Get-Phase2Findings.ps1")
. (Join-Path $PSScriptRoot "Get-Phase2AttackPaths.ps1")

$runId = [guid]::NewGuid().ToString()
$runTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
foreach ($dir in @($EvidenceOutputPath, (Split-Path $ClusterStorePath -Parent), $LogPath)) {
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}
$logFile = Join-Path $LogPath "Phase2_Log_$runTimestamp.txt"
function Write-Phase2Log {
    param([string]$Message, [ValidateSet("INFO","WARNING","ERROR","SUCCESS")][string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$ts [$Level] $Message" -ErrorAction SilentlyContinue
    $color = switch ($Level) { "ERROR" {"Red"} "WARNING" {"Yellow"} "SUCCESS" {"Green"} default {"Gray"} }
    Write-Host $Message -ForegroundColor $color
}
Write-Phase2Log "=== Phase 2 Intelligence Layer | RunId=$runId ===" "INFO"

if (-not (Test-Path $AutonomyMatrixPath)) { Write-Phase2Log "Autonomy matrix not found: $AutonomyMatrixPath" "ERROR"; exit 1 }
if (-not (Test-Path $Phase2ConfigPath))   { Write-Phase2Log "Phase 2 config not found: $Phase2ConfigPath" "ERROR"; exit 1 }
$matrix = Get-Content $AutonomyMatrixPath -Raw | ConvertFrom-Json
$config = Get-Content $Phase2ConfigPath -Raw | ConvertFrom-Json

$killActive = $ForcePropose -or (Test-Path $KillSwitchPath) -or $matrix.killSwitch.enabled
if ($killActive) { Write-Phase2Log "Kill switch / ForcePropose active -- no Auto executions will be triggered this run, reporting only." "WARNING" }
#endregion

#region ====================== FINDING TYPE MAP ======================
$findingTypeMap = Build-Phase2FindingTypeMap -ToolkitScriptsPath $ToolkitScriptsPath -Matrix $matrix
Write-Phase2Log "Matched $($findingTypeMap.Count) recommendation name(s) to Phase 1 scripts." "INFO"
#endregion

#region ====================== INGEST + NORMALIZE ======================
Write-Phase2Log "Querying Defender assessments + Policy non-compliance..." "INFO"
$defenderFindings = Get-Phase2DefenderFindings -SubscriptionIds $SubscriptionIds | ConvertTo-Phase2NormalizedFinding
$policyFindings    = Get-Phase2PolicyFindings | ConvertTo-Phase2NormalizedFinding
$allFindings = @($defenderFindings) + @($policyFindings)
Write-Phase2Log "Ingested $($allFindings.Count) raw findings ($($defenderFindings.Count) Defender, $($policyFindings.Count) Policy)." "INFO"

$attackPathMap = Get-Phase2AttackPathResourceMap -SubscriptionIds $SubscriptionIds
Write-Phase2Log "Attack path data covers $($attackPathMap.Count) resource(s)." "INFO"
#endregion

#region ====================== ENVIRONMENT RESOLUTION (per subscription, cached) ======================
$envCache = @{}
function Resolve-Phase2Environment {
    param([string]$SubscriptionId)
    if ($envCache.ContainsKey($SubscriptionId)) { return $envCache[$SubscriptionId] }
    $default = $matrix.environmentResolution.defaultIfUnresolved
    try {
        $sub = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
        $tags = $sub.Tags
        if (-not $tags -or $tags.Count -eq 0) {
            $subResource = Get-AzResource -ResourceId "/subscriptions/$SubscriptionId" -ErrorAction SilentlyContinue
            $tags = $subResource.Tags
        }
        $envTag = $tags[$matrix.environmentResolution.tagName]
        $critTag = $tags[$matrix.environmentResolution.criticalityTagName]
        $resolved =
            if (-not $envTag) { $default }
            elseif ($envTag -eq "NonProd") { "NonProd" }
            elseif ($envTag -eq "Prod" -and $critTag -eq "High") { "ProdHighRisk" }
            elseif ($envTag -eq "Prod" -and $critTag -eq "Low") { "ProdLow" }
            else { $default }
        $envCache[$SubscriptionId] = $resolved
        return $resolved
    } catch {
        Write-Phase2Log "Could not resolve environment for subscription $SubscriptionId : $($_.Exception.Message). Failing closed to '$default'." "WARNING"
        $envCache[$SubscriptionId] = $default
        return $default
    }
}
#endregion

#region ====================== CLUSTERING ======================
$clusterStore = if (Test-Path $ClusterStorePath) { Get-Content $ClusterStorePath -Raw | ConvertFrom-Json -AsHashtable } else { @{} }

$clusters = $allFindings | Group-Object -Property RecommendationName, SubscriptionId, ResourceGroup | ForEach-Object {
    $items = $_.Group
    $first = $items[0]
    $key = "$($first.RecommendationName)|$($first.SubscriptionId)|$($first.ResourceGroup)"

    $isRecurring = $false
    if ($clusterStore.ContainsKey($key)) {
        $days = (New-TimeSpan -Start ([datetime]$clusterStore[$key]) -End (Get-Date)).TotalDays
        if ($days -le $config.clusterWindowDays) { $isRecurring = $true }
    }
    $clusterStore[$key] = (Get-Date).ToString("o")

    $resourceIds = $items.ResourceId
    $hasAttackPath = $false
    $attackPathDetail = $null
    foreach ($rid in $resourceIds) {
        if ($attackPathMap.ContainsKey($rid.ToLower())) {
            $hasAttackPath = $true
            $attackPathDetail = $attackPathMap[$rid.ToLower()]
            break
        }
    }

    # Best-effort ownership sample: just the first resource, not every resource in the cluster.
    $ownerPresent = $false
    try {
        $sampleTags = (Get-AzResource -ResourceId $resourceIds[0] -ErrorAction SilentlyContinue).Tags
        if ($sampleTags -and $sampleTags["Owner"]) { $ownerPresent = $true }
    } catch { }

    $severity = ($items.Severity | Where-Object { $_ -ne "Unknown" } | Select-Object -First 1)
    if (-not $severity) { $severity = "Unknown" }

    [PSCustomObject]@{
        ClusterId          = [guid]::NewGuid().ToString()
        ClusterKey         = $key
        RecommendationName = $first.RecommendationName
        SubscriptionId      = $first.SubscriptionId
        ResourceGroup       = $first.ResourceGroup
        ResourceCount       = $resourceIds.Count
        ResourceIds         = $resourceIds
        Severity            = $severity
        Source              = ($items.Source | Select-Object -Unique) -join ","
        IsRecurring         = $isRecurring
        HasAttackPath       = $hasAttackPath
        AttackPathDisplayName = $attackPathDetail.DisplayName
        AttackPathRiskLevel   = $attackPathDetail.RiskLevel
        OwnerTagPresent     = $ownerPresent
    }
}
($clusterStore | ConvertTo-Json -Depth 6) | Set-Content -Path $ClusterStorePath
Write-Phase2Log "Grouped $($allFindings.Count) findings into $($clusters.Count) cluster(s)." "INFO"
#endregion

#region ====================== SCORING + DECISION ======================
$evidenceEntries = @()
$rollupAutoNotUrgent = @()

foreach ($cluster in $clusters) {
    $environment = Resolve-Phase2Environment -SubscriptionId $cluster.SubscriptionId
    $matched = $findingTypeMap[$cluster.RecommendationName]

    $score = 0
    $score += $config.scoring.severityWeights.$($cluster.Severity)
    if (-not $score) { $score = $config.scoring.severityWeights.Unknown }
    $score += $config.scoring.environmentWeights.$environment
    if ($cluster.IsRecurring) { $score += $config.scoring.recurringClusterBonus }
    if (-not $cluster.OwnerTagPresent) { $score += $config.scoring.unknownOwnerPenalty }
    if ($cluster.HasAttackPath) { $score += $config.scoring.attackPathBonus }

    # ---- Base decision ----
    $reasonParts = @()
    if ($matched) {
        $catDef = $matrix.categories.($matched.Category)
        $decision = $catDef.environments.$environment
        if (-not $decision) { $decision = "Propose" }
        $reasonParts += "matched to $($matched.Category)/$($matched.Script), matrix says $decision for $environment"
    } else {
        $decision = if ($cluster.Severity -eq "High") { $config.unmatchedFindingPolicy.highSeverityDecision } else { $config.unmatchedFindingPolicy.otherSeverityDecision }
        $reasonParts += "no Phase 1 script covers '$($cluster.RecommendationName)' -- visibility only, decision=$decision by severity"
    }

    if ($killActive) {
        $decision = "Propose"
        $reasonParts += "kill switch active, forced to Propose"
    }

    # ---- Attack-path policy: only ever escalates attention, never autonomy ----
    $isUrgent = $false
    if ($cluster.HasAttackPath -and -not $killActive) {
        if ($decision -eq "Auto") {
            $isUrgent = $true
            $reasonParts += "on active attack path ($($cluster.AttackPathDisplayName), risk=$($cluster.AttackPathRiskLevel)) -- still Auto, flagged urgent"
        } elseif ($decision -eq "Propose") {
            $decision = "Escalate"
            $reasonParts += "on active attack path ($($cluster.AttackPathDisplayName), risk=$($cluster.AttackPathRiskLevel)) -- upgraded Propose to Escalate"
        }
    }
    $decisionReason = $reasonParts -join "; "

    # ---- Execute (only matched + Auto + not paused) ----
    $phase1EvidenceFile = $null
    if ($matched -and $decision -eq "Auto" -and -not $killActive) {
        if ($PSCmdlet.ShouldProcess("$($cluster.ResourceCount) resource(s) via $($matched.Category)", "Invoke Phase 1 auto-remediation")) {
            Write-Phase2Log "  Triggering Phase 1 for category '$($matched.Category)' (cluster: $($cluster.RecommendationName) / $($cluster.ResourceGroup))" "INFO"
            try {
                & $Phase1OrchestratorPath -Category $matched.Category -EnvironmentOverride $environment
                $phase1EvidenceFile = Get-ChildItem -Path $Phase1EvidencePath -Filter "Phase1_Evidence_*.json" -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
            } catch {
                Write-Phase2Log "  Phase 1 invocation failed: $($_.Exception.Message)" "ERROR"
            }
        }
    }

    if ($decision -ne "Auto" -or $isUrgent) {
        $title = if ($isUrgent) { "URGENT (attack path): $($cluster.RecommendationName)" } else { "$decision`: $($cluster.RecommendationName)" }
        $text = "$($cluster.ResourceCount) resource(s) in $($cluster.ResourceGroup) ($environment). Score=$score. $decisionReason"
        if ($TeamsWebhookUrl) {
            try {
                $body = @{ title = $title; text = $text } | ConvertTo-Json
                Invoke-RestMethod -Uri $TeamsWebhookUrl -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
            } catch { Write-Phase2Log "  Teams notification failed: $($_.Exception.Message)" "WARNING" }
        }
    } elseif ($decision -eq "Auto") {
        $rollupAutoNotUrgent += "$($cluster.RecommendationName) ($($cluster.ResourceCount) in $($cluster.ResourceGroup))"
    }

    $evidenceEntries += [PSCustomObject]@{
        clusterId          = $cluster.ClusterId
        recommendationName = $cluster.RecommendationName
        subscriptionId      = $cluster.SubscriptionId
        resourceGroup       = $cluster.ResourceGroup
        resourceCount       = $cluster.ResourceCount
        environment         = $environment
        severity            = $cluster.Severity
        isRecurring         = $cluster.IsRecurring
        hasAttackPath       = $cluster.HasAttackPath
        priorityScore       = $score
        matchedCategory     = $matched.Category
        matchedScript       = $matched.Script
        decision            = $decision
        isUrgent            = $isUrgent
        decisionReason      = $decisionReason
        ownerTagPresent     = $cluster.OwnerTagPresent
        phase1EvidenceFile  = $phase1EvidenceFile
    }
}

# One rollup message for quiet Auto activity, instead of one Teams message per cluster.
if ($TeamsWebhookUrl -and $rollupAutoNotUrgent.Count -gt 0) {
    try {
        $body = @{ title = "Phase 2: routine Auto-remediation summary"; text = ($rollupAutoNotUrgent -join "`n") } | ConvertTo-Json
        Invoke-RestMethod -Uri $TeamsWebhookUrl -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
    } catch { Write-Phase2Log "Rollup Teams notification failed: $($_.Exception.Message)" "WARNING" }
}
#endregion

#region ====================== EVIDENCE + SUMMARY ======================
$evidencePackage = [PSCustomObject]@{
    schemaVersion    = "phase2-v1"
    runId            = $runId
    timestampUtc     = (Get-Date).ToUniversalTime().ToString("o")
    killSwitchActive = $killActive
    clusterCount     = $clusters.Count
    entries          = $evidenceEntries
}
$evidenceFile = Join-Path $EvidenceOutputPath "Phase2_Evidence_$runTimestamp.json"
($evidencePackage | ConvertTo-Json -Depth 10) | Set-Content -Path $evidenceFile

$summaryFile = Join-Path $EvidenceOutputPath "Phase2_Summary_$runTimestamp.csv"
$evidenceEntries | Select-Object recommendationName, subscriptionId, resourceGroup, resourceCount, environment, severity, priorityScore, decision, isUrgent |
    Export-Csv -Path $summaryFile -NoTypeInformation

Write-Phase2Log "" ; Write-Phase2Log "=== Run complete: $($clusters.Count) cluster(s) evaluated ===" "SUCCESS"
Write-Phase2Log "Evidence: $evidenceFile" "INFO"
Write-Phase2Log "Summary : $summaryFile" "INFO"
#endregion
