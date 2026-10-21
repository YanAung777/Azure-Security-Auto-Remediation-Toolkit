<#
.SYNOPSIS
    Phase 3 shared functions: proposals, approvals, feedback, intent validation.

.NOTES
    Storage is local JSON (one file per proposal; append-only JSONL for feedback), matching
    your Phase 2 choice. Local files are NOT tamper-evident -- anyone with write access to the
    folder can edit an approval. That is fine for a pilot; for the audit story, ship these
    folders to the immutable evidence Storage Account (Phase 0) on a schedule, or move the
    approval step to something that authenticates the approver server-side (Logic App /
    Power Automate). See README-Phase3.md.
#>

function Get-Phase3Config {
    param([string]$ConfigPath = (Join-Path $PSScriptRoot "phase3-config.json"))
    if (Test-Path $ConfigPath) { return Get-Content $ConfigPath -Raw | ConvertFrom-Json }
    throw "Phase 3 config not found: $ConfigPath"
}

function Get-Phase3Approver {
    # The approver is whoever is signed in to Azure, not a name typed on the command line.
    $ctx = Get-AzContext
    if (-not $ctx -or -not $ctx.Account.Id) { throw "No Azure context. Run Connect-AzAccount first -- approvals are recorded against the signed-in identity." }
    return $ctx.Account.Id
}

function Send-Phase3Teams {
    param([string]$WebhookUrl, [string]$Title, [string]$Text)
    if (-not $WebhookUrl) { return }
    try {
        Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body (@{ title = $Title; text = $Text } | ConvertTo-Json) -ContentType "application/json" -ErrorAction Stop | Out-Null
    } catch { Write-Warning "Teams notification failed: $($_.Exception.Message)" }
}

#region ---------------- proposals ----------------
function Save-Phase3Proposal {
    param($Proposal, [string]$ProposalStorePath)
    if (-not (Test-Path $ProposalStorePath)) { New-Item -ItemType Directory -Path $ProposalStorePath -Force | Out-Null }
    ($Proposal | ConvertTo-Json -Depth 8) | Set-Content -Path (Join-Path $ProposalStorePath "$($Proposal.proposalId).json")
}

function Get-Phase3Proposal {
    param([string]$ProposalStorePath, [string]$ProposalId, [string[]]$Status)
    if (-not (Test-Path $ProposalStorePath)) { return @() }
    $all = Get-ChildItem -Path $ProposalStorePath -Filter "*.json" | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json }
    if ($ProposalId) { $all = $all | Where-Object { $_.proposalId -eq $ProposalId } }
    if ($Status)     { $all = $all | Where-Object { $Status -contains $_.status } }
    return @($all)
}

function New-Phase3Proposal {
    <#
    One proposal per (script, subscription). The Fix scripts act on EVERY non-compliant resource
    in the current subscription, so "approve these 7 resources" is not something that can be
    honoured -- approval is for the script in the subscription, and execution re-checks that
    nothing new has appeared since (see Invoke-Phase1AutoRemediation.ps1 -ApprovalId).
    #>
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Script,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [Parameter(Mandatory)][string]$Environment,
        [ValidateSet("Propose","Escalate")][string]$Decision = "Propose",
        [int]$PriorityScore = 0,
        [bool]$HasAttackPath = $false,
        [Parameter(Mandatory)][string]$Phase1OrchestratorPath,
        [string]$KillSwitchPath,
        [Parameter(Mandatory)][string]$ProposalStorePath,
        [string]$TeamsWebhookUrl,
        [string]$ConfigPath = (Join-Path $PSScriptRoot "phase3-config.json")
    )
    $cfg = Get-Phase3Config -ConfigPath $ConfigPath

    # Live preview from Phase 1 itself, in the right subscription: its own snapshot is the source of
    # truth for "what would change", not Defender's (Defender assessments can lag by hours).
    $prior = Get-AzContext
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
        $p1 = @{ Category = $Category; PreviewOnly = $true; PassThru = $true }
        if ($KillSwitchPath) { $p1.KillSwitchPath = $KillSwitchPath }
        $pkg = & $Phase1OrchestratorPath @p1 | Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'entries' } | Select-Object -Last 1
    } finally {
        if ($prior) { Set-AzContext -SubscriptionId $prior.Subscription.Id | Out-Null }
    }

    $resourceIds = @($pkg.entries | Where-Object { $_.script -eq $Script -and $_.status -eq "ProposedNotExecuted" } | ForEach-Object { $_.resourceId })
    $existing = @(Get-Phase3Proposal -ProposalStorePath $ProposalStorePath -Status "Pending","Approved" |
        Where-Object { $_.script -eq $Script -and $_.subscriptionId -eq $SubscriptionId })

    if ($resourceIds.Count -eq 0) {
        foreach ($e in $existing) { $e.status = "Superseded"; $e | Add-Member -NotePropertyName note -NotePropertyValue "Nothing left to remediate at $((Get-Date).ToUniversalTime().ToString('o'))" -Force; Save-Phase3Proposal $e $ProposalStorePath }
        return $null
    }

    $fingerprint = ($resourceIds | ForEach-Object { $_.ToLower() } | Sort-Object) -join ","
    foreach ($e in $existing) {
        if ((($e.resourceIds | ForEach-Object { $_.ToLower() } | Sort-Object) -join ",") -eq $fingerprint) { return $e }   # unchanged: no new ping
        $e.status = "Superseded"; Save-Phase3Proposal $e $ProposalStorePath
    }

    $required = if ($Decision -eq "Escalate") { $cfg.fourEyes.requiredApprovalsEscalate }
                elseif ($Environment -eq "ProdHighRisk") { $cfg.fourEyes.requiredApprovalsProdHighRisk }
                else { $cfg.fourEyes.requiredApprovalsDefault }

    $now = (Get-Date).ToUniversalTime()
    $proposal = [PSCustomObject]@{
        schemaVersion     = "phase3-v1"
        proposalId        = ([guid]::NewGuid().ToString().Substring(0, 8))
        createdUtc        = $now.ToString("o")
        expiresUtc        = $now.AddHours($cfg.proposalExpiryHours).ToString("o")
        status            = "Pending"
        category          = $Category
        script            = $Script
        subscriptionId    = $SubscriptionId
        environment       = $Environment
        decision          = $Decision
        priorityScore     = $PriorityScore
        hasAttackPath     = $HasAttackPath
        resourceCount     = $resourceIds.Count
        resourceIds       = $resourceIds
        whatIfPreview     = [string]$pkg.previews.$Script
        requiredApprovals = [int]$required
        approvals         = @()
        approvedUtc       = $null
        rejection         = $null
        execution         = $null
    }
    Save-Phase3Proposal $proposal $ProposalStorePath

    $flag = if ($HasAttackPath) { " [ATTACK PATH]" } else { "" }
    Send-Phase3Teams -WebhookUrl $TeamsWebhookUrl -Title "Approval needed ($Decision)$flag`: $Script" -Text (
        "Proposal $($proposal.proposalId): $($resourceIds.Count) resource(s) in subscription $SubscriptionId ($Environment). " +
        "Needs $required approval(s) from distinct people. Expires $($proposal.expiresUtc).`n" +
        "Review: Submit-Phase3Decision.ps1 -ProposalId $($proposal.proposalId) -Decision Approve|Reject")
    return $proposal
}
#endregion

#region ---------------- feedback ----------------
function Add-Phase3Feedback {
    param([Parameter(Mandatory)][string]$FeedbackPath, [Parameter(Mandatory)]$Proposal, [Parameter(Mandatory)][string]$Action,
          [string]$ReasonCode, [string]$ReasonText, [Parameter(Mandatory)][string]$By)
    $dir = Split-Path $FeedbackPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $line = [PSCustomObject]@{
        atUtc = (Get-Date).ToUniversalTime().ToString("o"); proposalId = $Proposal.proposalId; category = $Proposal.category
        script = $Proposal.script; environment = $Proposal.environment; action = $Action
        reasonCode = $ReasonCode; reasonText = $ReasonText; by = $By
    } | ConvertTo-Json -Compress
    Add-Content -Path $FeedbackPath -Value $line
}
#endregion

#region ---------------- environment + natural-language intent ----------------
function Get-Phase3SubscriptionEnvironment {
    param([Parameter(Mandatory)][string]$SubscriptionId, [Parameter(Mandatory)]$Matrix)
    $default = $Matrix.environmentResolution.defaultIfUnresolved
    try {
        # Same lookup Phase 1 and Phase 2 use, so all three layers agree on what "Prod" means.
        $sub = Get-AzSubscription -SubscriptionId $SubscriptionId -ErrorAction Stop
        $tags = $sub.Tags
        if (-not $tags -or $tags.Count -eq 0) { $tags = (Get-AzResource -ResourceId "/subscriptions/$SubscriptionId" -ErrorAction SilentlyContinue).Tags }
        if (-not $tags) { return $default }
        $envTag  = $tags[$Matrix.environmentResolution.tagName]
        $critTag = $tags[$Matrix.environmentResolution.criticalityTagName]
        if (-not $envTag) { return $default }
        if ($envTag -eq "NonProd") { return "NonProd" }
        if ($envTag -eq "Prod" -and $critTag -eq "Low") { return "ProdLow" }
        if ($envTag -eq "Prod") { return "ProdHighRisk" }   # High or missing criticality: fail closed
        return $default
    } catch { return $default }
}

function Test-Phase3Intent {
    <#
    The language model's output is treated as UNTRUSTED input. Whatever it says, this validator
    decides what may happen, and its central rule is: natural language can NARROW scope or LOWER
    autonomy, never raise it. "Auto" is only ever what the Autonomy Matrix already says.
    #>
    param([Parameter(Mandatory)]$Intent, [Parameter(Mandatory)]$Matrix, [Parameter(Mandatory)]$Config)

    $errors = @(); $warnings = @()
    $allCats = @($Matrix.categories.PSObject.Properties.Name)
    $allEnvs = @("NonProd", "ProdLow", "ProdHighRisk")

    $mode = if ($Intent.mode) { [string]$Intent.mode } else { "Preview" }
    if ($Config.naturalLanguage.allowedModes -notcontains $mode) { $errors += "Mode '$mode' is not allowed. Use Preview, Propose or Run." }

    foreach ($prop in @("autonomy", "autonomyOverride", "forceAuto", "skipWhatIf", "skipApproval")) {
        if ($Intent.PSObject.Properties.Name -contains $prop -and $Intent.$prop -and "$($Intent.$prop)" -notmatch '^(Preview|Propose|false)$') {
            $errors += "Request tried to set '$prop' = '$($Intent.$prop)'. Natural-language requests cannot raise autonomy or skip safeguards; the Autonomy Matrix decides."
        }
    }

    $cats = @($Intent.categories | Where-Object { $_ })
    if ($cats.Count -eq 0) { $cats = $allCats }
    foreach ($c in $cats) { if ($allCats -notcontains $c) { $errors += "Category '$c' is not in the Autonomy Matrix, so there is no script to run for it." } }
    $exclude = @($Intent.excludeCategories | Where-Object { $_ })
    $cats = @($cats | Where-Object { $exclude -notcontains $_ -and $allCats -contains $_ })
    if ($cats.Count -eq 0 -and $errors.Count -eq 0) { $errors += "After exclusions no categories remain." }

    $envs = @($Intent.environments | Where-Object { $_ })
    if ($envs.Count -eq 0) { $envs = $allEnvs }
    foreach ($e in $envs) { if ($allEnvs -notcontains $e) { $errors += "Environment '$e' is not one of NonProd, ProdLow, ProdHighRisk." } }

    if (@($Intent.severities | Where-Object { $_ }).Count -gt 0) {
        if ($mode -eq "Run") { $errors += "Severity filters can't be honoured in Run mode: the Fix scripts act on every non-compliant resource, not just high-severity ones. Use Preview, or drop the severity filter." }
        else { $warnings += "Severity filter ignored: the Fix scripts are not severity-aware." }
    }
    if ($cats -contains "Defender" -and $mode -eq "Run") { $warnings += "Defender is capped at Propose by Phase 1 (its script acts across all subscriptions); it will not be executed." }

    $subs = @($Intent.subscriptionIds | Where-Object { $_ })
    foreach ($s in $subs) { if ($s -notmatch '^[0-9a-fA-F-]{36}$') { $errors += "'$s' is not a subscription GUID." } }

    return [PSCustomObject]@{
        Valid = ($errors.Count -eq 0); Errors = $errors; Warnings = $warnings
        Plan = [PSCustomObject]@{ Mode = $mode; Categories = $cats; Environments = $envs; SubscriptionIds = $subs }
    }
}
#endregion

Export-ModuleMember -Function Get-Phase3Config, Get-Phase3Approver, Send-Phase3Teams, Save-Phase3Proposal, Get-Phase3Proposal, New-Phase3Proposal, Add-Phase3Feedback, Get-Phase3SubscriptionEnvironment, Test-Phase3Intent
