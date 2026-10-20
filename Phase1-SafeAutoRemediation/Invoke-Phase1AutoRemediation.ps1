<#
.SYNOPSIS
    Phase 1 - Safe Auto-Remediation orchestrator.

.DESCRIPTION
    Wraps the existing, tested Fix-*.ps1 scripts from the Azure Security
    Auto-Remediation Toolkit with:
      - Environment resolution (subscription tags), fail-closed to ProdHighRisk
      - An Autonomy Matrix decision (Auto / Propose / Escalate) per category+environment
      - Mandatory -WhatIf preview capture before any real change
      - Resource tagging + structured JSON evidence on every Auto execution
      - Before/after diffing so evidence and tags only touch resources that
        actually changed (no edits to the original Fix- scripts required)
      - Basic recurrence tracking (has this exact resource+finding been fixed before?)
      - A kill switch that forces everything to Propose, no matter what the matrix says
      - A hard scoping override for the Defender category (see comments below)

    This script does NOT modify any file under the original toolkit folder.
    It is designed to sit next to it and call it.

.NOTES
    Deferred to later phases (do not assume these exist yet):
      - Clustering / noise suppression across resources (Phase 2)
      - Priority scoring, ownership enrichment, attack-path awareness (Phase 2-3)
      - Real ITSM ticket creation (this script only writes a ticket-request
        JSON stub -- wire it to ServiceNow/Jira in Phase 1's later weeks or Phase 2)
      - Azure Table / Log Analytics-backed recurrence store (this script uses a
        local JSON file by default; swap Get-/Save-RecurrenceStore for a Table
        Storage or Log Analytics client when you're ready -- the interface is
        isolated to those two functions on purpose)
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateSet("Storage", "KeyVault", "AppServices", "Defender", "All")]
    [string]$Category = "All",

    # Folder containing the ORIGINAL, unmodified toolkit scripts.
    [string]$ToolkitScriptsPath = "..\Azure-Security-Auto-Remediation-Toolkit-main\Auto Remediation Azure Security Recommendations",

    [string]$AutonomyMatrixPath = ".\autonomy-matrix.json",
    [string]$EvidenceOutputPath = ".\evidence",
    [string]$StateStorePath = ".\state\RemediationHistory.json",
    [string]$LogPath = ".\logs",

    # Emergency stop: if this file exists, OR killSwitch.enabled=true in the
    # matrix JSON, every decision is forced to Propose this run.
    [string]$KillSwitchPath = ".\PAUSE_AUTOREMEDIATION",

    # Testing/manual override of environment resolution. Leave blank in production
    # so real subscription tags are used.
    [ValidateSet("", "NonProd", "ProdLow", "ProdHighRisk")]
    [string]$EnvironmentOverride = "",

    [string]$TeamsWebhookUrl,

    # Safety valve: forces Propose for every category regardless of matrix.
    # Use this for the first few pilot runs even in categories marked Auto.
    [switch]$ForcePropose,

    [int]$RecurrenceWindowDays = 30
)

#region ====================== SETUP ======================
$runId = [guid]::NewGuid().ToString()
$startTime = Get-Date
$runTimestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

foreach ($dir in @($EvidenceOutputPath, (Split-Path $StateStorePath -Parent), $LogPath)) {
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

$logFile = Join-Path $LogPath "Phase1_Log_$runTimestamp.txt"

function Write-Phase1Log {
    param([string]$Message, [ValidateSet("INFO","WARNING","ERROR","SUCCESS")][string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $logFile -Value "$ts [$Level] $Message" -ErrorAction SilentlyContinue
    $color = switch ($Level) { "ERROR" {"Red"} "WARNING" {"Yellow"} "SUCCESS" {"Green"} default {"Gray"} }
    Write-Host $Message -ForegroundColor $color
}

Write-Phase1Log "=== Phase 1 Safe Auto-Remediation | RunId=$runId | Category=$Category ===" "INFO"
#endregion

#region ====================== LOAD MATRIX ======================
if (-not (Test-Path $AutonomyMatrixPath)) {
    Write-Phase1Log "Autonomy matrix not found at $AutonomyMatrixPath. Aborting." "ERROR"
    exit 1
}
$matrix = Get-Content $AutonomyMatrixPath -Raw | ConvertFrom-Json
#endregion

#region ====================== KILL SWITCH ======================
function Test-KillSwitchActive {
    if ($ForcePropose) { return $true, "ForcePropose switch set on this run" }
    if (Test-Path $KillSwitchPath) { return $true, "Kill switch file present: $KillSwitchPath" }
    if ($matrix.killSwitch.enabled) { return $true, "killSwitch.enabled=true in $AutonomyMatrixPath ($($matrix.killSwitch.reason))" }
    return $false, $null
}
$killActive, $killReason = Test-KillSwitchActive
if ($killActive) {
    Write-Phase1Log "KILL SWITCH ACTIVE: $killReason -- every decision this run is forced to Propose." "WARNING"
}
#endregion

#region ====================== ENVIRONMENT RESOLUTION ======================
function Resolve-Phase1Environment {
    # Returns one of: NonProd, ProdLow, ProdHighRisk
    if ($EnvironmentOverride) {
        Write-Phase1Log "Environment resolution overridden to '$EnvironmentOverride' via parameter." "WARNING"
        return $EnvironmentOverride
    }

    $default = $matrix.environmentResolution.defaultIfUnresolved
    try {
        $ctx = Get-AzContext -ErrorAction Stop
        if (-not $ctx) { throw "No Azure context." }
        $subId = $ctx.Subscription.Id
        $sub = Get-AzSubscription -SubscriptionId $subId -ErrorAction Stop

        # Tags on the Az.Accounts subscription object; fall back to Resources API if empty.
        $tags = $sub.Tags
        if (-not $tags -or $tags.Count -eq 0) {
            $subResource = Get-AzResource -ResourceId "/subscriptions/$subId" -ErrorAction SilentlyContinue
            $tags = $subResource.Tags
        }

        $envTag = $tags[$matrix.environmentResolution.tagName]
        $critTag = $tags[$matrix.environmentResolution.criticalityTagName]

        if (-not $envTag) {
            Write-Phase1Log "Subscription '$($sub.Name)' has no '$($matrix.environmentResolution.tagName)' tag. Failing closed to '$default'." "WARNING"
            return $default
        }
        if ($envTag -eq "NonProd") { return "NonProd" }
        if ($envTag -eq "Prod") {
            if ($critTag -eq "High") { return "ProdHighRisk" }
            if ($critTag -eq "Low") { return "ProdLow" }
            Write-Phase1Log "Subscription '$($sub.Name)' tagged Prod with no/unknown Criticality tag. Failing closed to 'ProdHighRisk'." "WARNING"
            return "ProdHighRisk"
        }
        Write-Phase1Log "Unrecognized Environment tag value '$envTag'. Failing closed to '$default'." "WARNING"
        return $default
    } catch {
        Write-Phase1Log "Could not resolve environment ($($_.Exception.Message)). Failing closed to '$default'." "WARNING"
        return $default
    }
}

$currentEnvironment = Resolve-Phase1Environment
Write-Phase1Log "Resolved environment for this run: $currentEnvironment" "INFO"
#endregion

#region ====================== RECURRENCE STORE (local JSON; swap for Table/Log Analytics later) ======================
function Get-RecurrenceStore {
    if (Test-Path $StateStorePath) {
        return (Get-Content $StateStorePath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue)
    }
    return @{}
}
function Save-RecurrenceStore($store) {
    ($store | ConvertTo-Json -Depth 6) | Set-Content -Path $StateStorePath
}
function Test-Phase1Recurrence {
    param($store, [string]$ResourceId, [string]$FindingType)
    $key = "$ResourceId|$FindingType"
    if ($store.ContainsKey($key)) {
        $last = [datetime]$store[$key]
        $days = (New-TimeSpan -Start $last -End (Get-Date)).TotalDays
        if ($days -le $RecurrenceWindowDays) {
            return $true, [math]::Round($days, 1)
        }
    }
    return $false, $null
}
function Set-Phase1RecurrenceRecord {
    param($store, [string]$ResourceId, [string]$FindingType)
    $store["$ResourceId|$FindingType"] = (Get-Date).ToString("o")
    return $store
}
$recurrenceStore = Get-RecurrenceStore
#endregion

#region ====================== RESOURCE SNAPSHOT + COMPLIANCE PREDICATES ======================
# One snapshot function per category. Each returns a flat list of PSCustomObjects
# with a ResourceId so before/after runs can be diffed per resource.

function Get-Phase1StorageSnapshot {
    Get-AzStorageAccount -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            ResourceId = $_.Id
            ResourceGroup = $_.ResourceGroupName
            Name = $_.StorageAccountName
            MinimumTlsVersion = $_.MinimumTlsVersion
            EnableHttpsTrafficOnly = $_.EnableHttpsTrafficOnly
            AllowBlobPublicAccess = $_.AllowBlobPublicAccess
        }
    }
}
function Get-Phase1KeyVaultSnapshot {
    Get-AzKeyVault -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            ResourceId = $_.ResourceId
            ResourceGroup = $_.ResourceGroupName
            Name = $_.VaultName
            EnableSoftDelete = $_.EnableSoftDelete
            EnablePurgeProtection = $_.EnablePurgeProtection
            EnableRbacAuthorization = $_.EnableRbacAuthorization
        }
    }
}
function Get-Phase1AppServiceSnapshot {
    Get-AzFunctionApp -ErrorAction SilentlyContinue | ForEach-Object {
        $cfg = Get-AzWebApp -ResourceGroupName $_.ResourceGroupName -Name $_.Name -ErrorAction SilentlyContinue
        if ($cfg) {
            [PSCustomObject]@{
                ResourceId = $cfg.Id
                ResourceGroup = $cfg.ResourceGroupName
                Name = $cfg.Name
                HttpsOnly = $cfg.HttpsOnly
                MinTlsVersion = $cfg.SiteConfig.MinTlsVersion
            }
        }
    }
}
function Get-Phase1DefenderSnapshot {
    # Current subscription context only -- see the Defender scoping override below.
    Get-AzSecurityPricing -ErrorAction SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{
            ResourceId = "/subscriptions/$((Get-AzContext).Subscription.Id)/providers/Microsoft.Security/pricings/$($_.Name)"
            ResourceGroup = $null
            Name = $_.Name
            PricingTier = $_.PricingTier
        }
    }
}

$snapshotFunctions = @{
    "Storage"      = ${function:Get-Phase1StorageSnapshot}
    "KeyVault"     = ${function:Get-Phase1KeyVaultSnapshot}
    "AppServices"  = ${function:Get-Phase1AppServiceSnapshot}
    "Defender"     = ${function:Get-Phase1DefenderSnapshot}
}

# Per-script compliance predicate: given one snapshot row, is this resource
# already compliant for that specific script's check?
$compliancePredicates = @{
    "Fix-StorageAccountTLS.ps1"            = { param($r) $r.MinimumTlsVersion -eq "TLS1_2" }
    "Fix-StorageSecureTransfer.ps1"        = { param($r) $r.EnableHttpsTrafficOnly -eq $true }
    "Fix-StoragePublicBlobAccess.ps1"      = { param($r) $r.AllowBlobPublicAccess -eq $false }
    "Fix-EnableKeyVaultSoftDelete.ps1"     = { param($r) $r.EnableSoftDelete -eq $true }
    "Fix-EnableKeyVaultPurgeProtection.ps1"= { param($r) $r.EnablePurgeProtection -eq $true }
    "Fix-EnableKeyVaultRBAC.ps1"           = { param($r) $r.EnableRbacAuthorization -eq $true }
    "Fix-FunctionAppHTTPSOnly.ps1"         = { param($r) $r.HttpsOnly -eq $true }
    "Fix-FunctionAppMinimumTLS.ps1"        = { param($r) $r.MinTlsVersion -eq "1.2" }
    "Fix-EnableDefenderPlans.ps1"          = { param($r) $r.PricingTier -eq "Standard" }
}
#endregion

#region ====================== TAGGING + EVIDENCE ======================
function Set-Phase1RemediationTags {
    param([string]$ResourceId, [string]$ScriptName)
    try {
        Update-AzTag -ResourceId $ResourceId -Tag @{
            "remediated-by"      = "Phase1AutoRemediation"
            "remediated-at"      = (Get-Date -Format "o")
            "remediation-script" = $ScriptName
        } -Operation Merge -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Phase1Log "  Tagging failed for $ResourceId : $($_.Exception.Message)" "WARNING"
        return $false
    }
}

function Send-Phase1TeamsNotification {
    param([string]$Title, [string]$Text)
    if (-not $TeamsWebhookUrl) { return }
    try {
        $body = @{ title = $Title; text = $Text } | ConvertTo-Json
        Invoke-RestMethod -Uri $TeamsWebhookUrl -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
    } catch {
        Write-Phase1Log "  Teams notification failed: $($_.Exception.Message)" "WARNING"
    }
}

function New-Phase1TicketStub {
    # Placeholder for ServiceNow/Jira integration. Writes a ticket-request JSON
    # that a Phase 1(b)/Phase 2 Logic App or Function can pick up and file for real.
    param([string]$Category, [string]$Script, [string]$Decision, [array]$AffectedResources, [string]$WhatIfPreview)
    $ticket = [PSCustomObject]@{
        ticketRequestId = [guid]::NewGuid().ToString()
        createdAtUtc    = (Get-Date).ToUniversalTime().ToString("o")
        category        = $Category
        script          = $Script
        decision        = $Decision
        affectedCount   = $AffectedResources.Count
        affectedResourceIds = $AffectedResources.ResourceId
        whatIfPreview   = $WhatIfPreview
        status          = "PendingITSMCreation"
    }
    $path = Join-Path $EvidenceOutputPath "TicketRequest_$($Category)_$($Script)_$runTimestamp.json"
    ($ticket | ConvertTo-Json -Depth 6) | Set-Content -Path $path
    Write-Phase1Log "  Ticket-request stub written: $path (wire to ServiceNow/Jira in a later iteration)" "INFO"
}
#endregion

#region ====================== CORE LOOP ======================
$evidenceEntries = @()
$summaryResults = @()

$categoriesToRun = if ($Category -eq "All") { $matrix.categories.PSObject.Properties.Name } else { @($Category) }

foreach ($cat in $categoriesToRun) {
    $catDef = $matrix.categories.$cat
    Write-Phase1Log "" ; Write-Phase1Log "=== Category: $cat ===" "INFO"

    foreach ($scriptName in $catDef.scripts) {
        $scriptFile = Join-Path $ToolkitScriptsPath $scriptName
        if (-not (Test-Path $scriptFile)) {
            Write-Phase1Log "  Script not found, skipping: $scriptFile" "ERROR"
            continue
        }

        # ---- Decide: Auto / Propose / Escalate ----
        $decision = $catDef.environments.$currentEnvironment
        if (-not $decision) { $decision = "Propose" }
        if ($killActive) { $decision = "Propose" }

        # Hard override: Defender's underlying script loops ALL subscriptions
        # internally and ignores the current context, so it cannot safely be
        # trusted with "Auto" until it accepts a -SubscriptionId parameter.
        if ($cat -eq "Defender" -and $decision -eq "Auto") {
            Write-Phase1Log "  Overriding Defender decision Auto -> Propose: $scriptName iterates all subscriptions internally (scoping mismatch, see matrix _scopingWarning)." "WARNING"
            $decision = "Propose"
        }

        Write-Phase1Log "  Script: $scriptName | Environment: $currentEnvironment | Decision: $decision" "INFO"

        # ---- Snapshot BEFORE ----
        $snapshotFn = $snapshotFunctions[$cat]
        $before = & $snapshotFn
        $predicate = $compliancePredicates[$scriptName]
        $nonCompliantBefore = $before | Where-Object { -not (& $predicate $_) }

        if ($nonCompliantBefore.Count -eq 0) {
            Write-Phase1Log "  No non-compliant resources found. Nothing to do." "SUCCESS"
            continue
        }

        # ---- Always run -WhatIf first, capture preview text ----
        $whatIfPreview = & $scriptFile -WhatIf 2>&1 | Out-String

        $status = "Skipped"
        $tagged = @()

        if ($decision -eq "Auto") {
            if ($PSCmdlet.ShouldProcess("$($nonCompliantBefore.Count) resource(s) in $cat", "Run $scriptName for real")) {
                try {
                    & $scriptFile 2>&1 | Out-Null
                    $status = "Executed"
                } catch {
                    $status = "Failed"
                    Write-Phase1Log "  Execution failed: $($_.Exception.Message)" "ERROR"
                }
            }

            # ---- Snapshot AFTER, diff, tag, track recurrence ----
            $after = & $snapshotFn
            $afterById = @{}
            foreach ($r in $after) { $afterById[$r.ResourceId] = $r }

            foreach ($resBefore in $nonCompliantBefore) {
                $resAfter = $afterById[$resBefore.ResourceId]
                $nowCompliant = $resAfter -and (& $predicate $resAfter)
                if ($nowCompliant) {
                    $tagOk = Set-Phase1RemediationTags -ResourceId $resBefore.ResourceId -ScriptName $scriptName
                    $tagged += $resBefore.ResourceId

                    $isRecurring, $daysSinceLastFix = Test-Phase1Recurrence -store $recurrenceStore -ResourceId $resBefore.ResourceId -FindingType $scriptName
                    if ($isRecurring) {
                        Write-Phase1Log "  DRIFT: $($resBefore.Name) was fixed for '$scriptName' $daysSinceLastFix day(s) ago and is non-compliant again." "WARNING"
                    }
                    $recurrenceStore = Set-Phase1RecurrenceRecord -store $recurrenceStore -ResourceId $resBefore.ResourceId -FindingType $scriptName

                    $evidenceEntries += [PSCustomObject]@{
                        resourceId       = $resBefore.ResourceId
                        resourceName     = $resBefore.Name
                        category         = $cat
                        script           = $scriptName
                        decision         = "Auto"
                        status           = "Remediated"
                        beforeState      = $resBefore
                        afterState       = $resAfter
                        tagged           = $tagOk
                        isRecurring      = $isRecurring
                        daysSinceLastFix = $daysSinceLastFix
                        # Phase 2+ fields, intentionally null until the Intelligence Layer exists:
                        priorityScore    = $null
                        clusterId        = $null
                        owner            = $null
                    }
                } else {
                    Write-Phase1Log "  $($resBefore.Name) still non-compliant after execution -- check manually." "WARNING"
                    $evidenceEntries += [PSCustomObject]@{
                        resourceId = $resBefore.ResourceId; resourceName = $resBefore.Name
                        category = $cat; script = $scriptName; decision = "Auto"
                        status = "AttemptedNoChange"; beforeState = $resBefore; afterState = $resAfter
                        tagged = $false; isRecurring = $false; daysSinceLastFix = $null
                        priorityScore = $null; clusterId = $null; owner = $null
                    }
                }
            }

            Send-Phase1TeamsNotification -Title "Phase 1 Auto-Remediation: $scriptName" `
                -Text "$($tagged.Count)/$($nonCompliantBefore.Count) resource(s) auto-remediated in $currentEnvironment."

        } else {
            # Propose or Escalate: no execution, just evidence + ticket stub.
            foreach ($res in $nonCompliantBefore) {
                $evidenceEntries += [PSCustomObject]@{
                    resourceId = $res.ResourceId; resourceName = $res.Name
                    category = $cat; script = $scriptName; decision = $decision
                    status = "ProposedNotExecuted"; beforeState = $res; afterState = $null
                    tagged = $false; isRecurring = $null; daysSinceLastFix = $null
                    priorityScore = $null; clusterId = $null; owner = $null
                }
            }
            New-Phase1TicketStub -Category $cat -Script $scriptName -Decision $decision `
                -AffectedResources $nonCompliantBefore -WhatIfPreview $whatIfPreview
            $status = $decision
        }

        $summaryResults += [PSCustomObject]@{
            Category = $cat; Script = $scriptName; Environment = $currentEnvironment
            Decision = $decision; NonCompliantFound = $nonCompliantBefore.Count
            Remediated = $tagged.Count; Status = $status; Timestamp = Get-Date
        }
    }
}
Save-RecurrenceStore $recurrenceStore
#endregion

#region ====================== EVIDENCE PACKAGE + SUMMARY ======================
$evidencePackage = [PSCustomObject]@{
    schemaVersion  = "phase1-v1"
    runId          = $runId
    timestampUtc   = (Get-Date).ToUniversalTime().ToString("o")
    triggeredBy    = "Manual"
    environment    = $currentEnvironment
    killSwitchActive = $killActive
    autonomyMatrixVersion = $matrix.schemaVersion
    entries        = $evidenceEntries
    summary        = @{
        totalFindingsEvaluated = ($summaryResults | Measure-Object -Property NonCompliantFound -Sum).Sum
        totalRemediated         = ($summaryResults | Measure-Object -Property Remediated -Sum).Sum
    }
    # Phase 2+ fields, present so downstream tooling can rely on the shape existing:
    soc2Mapping    = @()
    evidenceLocation = $null
}
$evidenceFile = Join-Path $EvidenceOutputPath "Phase1_Evidence_$runTimestamp.json"
($evidencePackage | ConvertTo-Json -Depth 10) | Set-Content -Path $evidenceFile
$evidencePackage.evidenceLocation = $evidenceFile

$summaryFile = Join-Path $EvidenceOutputPath "Phase1_Summary_$runTimestamp.csv"
$summaryResults | Export-Csv -Path $summaryFile -NoTypeInformation

Write-Phase1Log "" ; Write-Phase1Log "=== Run complete ===" "SUCCESS"
Write-Phase1Log "Evidence: $evidenceFile" "INFO"
Write-Phase1Log "Summary : $summaryFile" "INFO"
Write-Phase1Log "Total findings evaluated: $($evidencePackage.summary.totalFindingsEvaluated) | Remediated: $($evidencePackage.summary.totalRemediated)" "INFO"
#endregion
