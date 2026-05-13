<#
.SYNOPSIS
    Bulk Remediate Non-Compliant Azure Policy Resources
    Safely triggers remediation tasks for all (or selected) non-compliant resources.

    # 1. Dry run first (recommended)
.\Remediate-NonCompliantResources.ps1 -WhatIf

# 2. Remediate top 500 non-compliant resources
.\Remediate-NonCompliantResources.ps1

# 3. Remediate only specific policy assignments
.\Remediate-NonCompliantResources.ps1 -PolicyAssignmentIds "/subscriptions/xxx/providers/Microsoft.Authorization/policyAssignments/Assign-Defender"
#>

param(
    [switch]$WhatIf,
    [string[]]$PolicyAssignmentIds = @(),     # Optional: Filter by specific assignments
    [int]$Top = 500,                          # Limit to prevent overwhelming the system
    [switch]$IncludeExempted = $false
)

Write-Host "=== Azure Policy Bulk Remediation ===" -ForegroundColor Cyan

# Get non-compliant policy states
if ($PolicyAssignmentIds.Count -gt 0) {
    $nonCompliant = Get-AzPolicyState -Filter "ComplianceState eq 'NonCompliant'" | 
                    Where-Object { $_.PolicyAssignmentId -in $PolicyAssignmentIds } |
                    Select-Object -First $Top
} else {
    $nonCompliant = Get-AzPolicyState -Filter "ComplianceState eq 'NonCompliant'" | 
                    Select-Object -First $Top
}

if ($nonCompliant.Count -eq 0) {
    Write-Host "No non-compliant resources found." -ForegroundColor Green
    return
}

Write-Host "Found $($nonCompliant.Count) non-compliant resources.`n" -ForegroundColor Yellow

$remediatedCount = 0

foreach ($item in $nonCompliant) {
    $policyName = $item.PolicyDefinitionName
    $resourceId = $item.ResourceId
    $assignmentId = $item.PolicyAssignmentId

    Write-Host "Remediating: $policyName → $resourceId" -ForegroundColor Cyan

    if (-not $WhatIf) {
        try {
            $remediationName = "AutoRemediation-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

            Start-AzPolicyRemediation `
                -Name $remediationName `
                -PolicyAssignmentId $assignmentId `
                -ResourceId $resourceId `
                -ErrorAction Stop | Out-Null

            Write-Host "  ✓ Remediation task started" -ForegroundColor Green
            $remediatedCount++
        }
        catch {
            Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [WhatIf] Would start remediation for $resourceId" -ForegroundColor Gray
    }
}

Write-Host "`n=== Bulk Remediation Summary ===" -ForegroundColor Cyan
Write-Host "Total resources processed : $($nonCompliant.Count)" -ForegroundColor Gray
Write-Host "Remediation tasks started : $remediatedCount" -ForegroundColor Green

if ($remediatedCount -gt 0) {
    Write-Host "`nNote: Remediation tasks run asynchronously. Check status in Azure Portal > Policy > Remediation." -ForegroundColor Yellow
}