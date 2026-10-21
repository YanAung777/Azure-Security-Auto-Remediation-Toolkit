<#
.SYNOPSIS
    Approve or reject a remediation proposal. Rejections require a reason, which feeds the learning store.

.DESCRIPTION
    - The approver is the signed-in Azure identity, not a typed name.
    - Proposals that need two approvals (Escalate, or ProdHighRisk) require two DIFFERENT people.
    - There is deliberately no "approve with modifications": the Fix scripts act on every
      non-compliant resource in the subscription and can't be narrowed to a subset. If the scope
      is wrong, reject with -ReasonCode WrongScope and say what you'd want in -Comment.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProposalId,
    [Parameter(Mandatory)][ValidateSet("Approve","Reject")][string]$Decision,
    [ValidateSet("ApplicationDependency","ChangeFreeze","FalseFinding","WrongScope","WillFixViaIaC","RiskAccepted","Other")][string]$ReasonCode,
    [string]$Comment,
    [string]$ProposalStorePath = (Join-Path $PSScriptRoot "state/Proposals"),
    [string]$FeedbackPath = (Join-Path $PSScriptRoot "state/Feedback.jsonl"),
    [string]$TeamsWebhookUrl
)
Import-Module (Join-Path $PSScriptRoot "Phase3-Common.psm1") -Force

$proposal = Get-Phase3Proposal -ProposalStorePath $ProposalStorePath -ProposalId $ProposalId | Select-Object -First 1
if (-not $proposal) { throw "Proposal '$ProposalId' not found in $ProposalStorePath." }
if ($proposal.status -ne "Pending") { throw "Proposal $ProposalId is '$($proposal.status)', not Pending." }
if ([datetime]$proposal.expiresUtc -lt (Get-Date).ToUniversalTime()) {
    $proposal.status = "Expired"; Save-Phase3Proposal $proposal $ProposalStorePath
    throw "Proposal $ProposalId expired at $($proposal.expiresUtc). It will be re-created on the next Phase 2 run if the findings are still open."
}
$approver = Get-Phase3Approver
$nowUtc = (Get-Date).ToUniversalTime().ToString("o")

if ($Decision -eq "Reject") {
    if (-not $ReasonCode) { throw "-ReasonCode is required when rejecting." }
    if ($ReasonCode -eq "Other" -and -not $Comment) { throw "-Comment is required when the reason code is 'Other'." }
    $proposal.status = "Rejected"
    $proposal.rejection = [PSCustomObject]@{ by = $approver; atUtc = $nowUtc; reasonCode = $ReasonCode; comment = $Comment }
    Save-Phase3Proposal $proposal $ProposalStorePath
    Add-Phase3Feedback -FeedbackPath $FeedbackPath -Proposal $proposal -Action "Rejected" -ReasonCode $ReasonCode -ReasonText $Comment -By $approver
    Write-Host "Rejected $ProposalId ($ReasonCode). Recorded for the learning store." -ForegroundColor Yellow
    Send-Phase3Teams -WebhookUrl $TeamsWebhookUrl -Title "Rejected: $($proposal.script)" -Text "Proposal $ProposalId rejected by $approver. Reason: $ReasonCode. $Comment"
    return
}

if (@($proposal.approvals | Where-Object { $_.by -eq $approver }).Count -gt 0) { throw "$approver has already approved $ProposalId. This proposal needs $($proposal.requiredApprovals) approvals from different people." }
$proposal.approvals = @($proposal.approvals) + [PSCustomObject]@{ by = $approver; atUtc = $nowUtc; comment = $Comment }
if (@($proposal.approvals).Count -ge $proposal.requiredApprovals) {
    $proposal.status = "Approved"; $proposal.approvedUtc = $nowUtc
    Write-Host "Approved ($(@($proposal.approvals).Count)/$($proposal.requiredApprovals)). Eligible for execution; the approval lapses after the window in phase3-config.json." -ForegroundColor Green
} else {
    Write-Host "Recorded approval $(@($proposal.approvals).Count)/$($proposal.requiredApprovals). Waiting for another approver." -ForegroundColor Cyan
}
Save-Phase3Proposal $proposal $ProposalStorePath
Add-Phase3Feedback -FeedbackPath $FeedbackPath -Proposal $proposal -Action "Approved" -ReasonText $Comment -By $approver
Send-Phase3Teams -WebhookUrl $TeamsWebhookUrl -Title "Approval recorded: $($proposal.script)" -Text "Proposal $ProposalId approved by $approver ($(@($proposal.approvals).Count)/$($proposal.requiredApprovals))."
