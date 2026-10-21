<#
.SYNOPSIS
    Executes fully-approved proposals through Phase 1 -- the only component that touches Azure resources.

.DESCRIPTION
    Safeguards, in order:
      1. Kill switch file present -> nothing executes.
      2. Approval older than approvalValidHours -> lapses (status Expired).
      3. Phase 1 re-checks, at execution time, that every resource the script would change is in the
         set the approvers saw. If anything new has appeared the run aborts (status Stale) and a fresh
         proposal is raised by the next Phase 2 run. Approvals never cover things nobody looked at.
      4. Phase 1's own rules still apply (WhatIf preview, tagging, evidence, Defender cap).
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ProposalStorePath = (Join-Path $PSScriptRoot "state/Proposals"),
    [string]$Phase1OrchestratorPath = (Join-Path $PSScriptRoot "../Phase1-SafeAutoRemediation/Invoke-Phase1AutoRemediation.ps1"),
    [string]$KillSwitchPath = (Join-Path $PSScriptRoot "../Phase1-SafeAutoRemediation/PAUSE_AUTOREMEDIATION"),
    [string]$TeamsWebhookUrl
)
Import-Module (Join-Path $PSScriptRoot "Phase3-Common.psm1") -Force
$cfg = Get-Phase3Config

if (Test-Path $KillSwitchPath) { Write-Warning "Kill switch present ($KillSwitchPath). Nothing will be executed."; return }

foreach ($p in (Get-Phase3Proposal -ProposalStorePath $ProposalStorePath -Status "Approved")) {
    $age = (New-TimeSpan -Start ([datetime]$p.approvedUtc) -End (Get-Date).ToUniversalTime()).TotalHours
    if ($age -gt $cfg.approvalValidHours) {
        $p.status = "Expired"; Save-Phase3Proposal $p $ProposalStorePath
        Write-Host "[$($p.proposalId)] approval lapsed ($([math]::Round($age,1))h old) -- not executed." -ForegroundColor Yellow
        continue
    }
    if (-not $PSCmdlet.ShouldProcess("$($p.script) in subscription $($p.subscriptionId) ($($p.resourceCount) resources)", "Execute approved proposal $($p.proposalId)")) { continue }

    Write-Host "[$($p.proposalId)] executing $($p.script) in $($p.subscriptionId) ..." -ForegroundColor Cyan
    $prior = Get-AzContext
    try {
        Set-AzContext -SubscriptionId $p.subscriptionId -ErrorAction Stop | Out-Null
        $pkg = & $Phase1OrchestratorPath -Category $p.category -ApprovalId $p.proposalId -ApprovedScript $p.script `
                   -ApprovedResourceIds $p.resourceIds -KillSwitchPath $KillSwitchPath -PassThru |
               Where-Object { $_ -and $_.PSObject.Properties.Name -contains 'entries' } | Select-Object -Last 1
        $result = $pkg.scriptResults | Where-Object { $_.Script -eq $p.script } | Select-Object -First 1
        $done = @($pkg.entries | Where-Object { $_.script -eq $p.script -and $_.status -eq "Remediated" }).Count
        $outcome = if ($result.Status -eq "ApprovalStale") { "Stale" } elseif ($pkg) { "Executed" } else { "Failed" }
        $p.status = $outcome
        $p.execution = [PSCustomObject]@{ atUtc = (Get-Date).ToUniversalTime().ToString("o"); remediated = $done; phase1EvidenceFile = $pkg.evidenceLocation }
    } catch {
        $p.status = "Failed"
        $p.execution = [PSCustomObject]@{ atUtc = (Get-Date).ToUniversalTime().ToString("o"); error = $_.Exception.Message }
    } finally {
        if ($prior) { Set-AzContext -SubscriptionId $prior.Subscription.Id | Out-Null }
    }
    Save-Phase3Proposal $p $ProposalStorePath
    $color = if ($p.status -eq "Executed") { "Green" } else { "Yellow" }
    Write-Host "[$($p.proposalId)] -> $($p.status)" -ForegroundColor $color
    Send-Phase3Teams -WebhookUrl $TeamsWebhookUrl -Title "Approved proposal $($p.status): $($p.script)" -Text "Proposal $($p.proposalId): $($p.status). Remediated: $($p.execution.remediated)."
}
