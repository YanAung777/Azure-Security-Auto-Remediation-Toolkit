<#
.SYNOPSIS
    Auto-remediate non-compliant Azure Policies where remediation is available
#>

param([switch]$WhatIf)

Write-Host "=== Starting Policy Auto-Remediation ===" -ForegroundColor Cyan

$nonCompliant = Get-AzPolicyState | Where-Object { $_.ComplianceState -eq "NonCompliant" }

foreach ($item in $nonCompliant) {
    $policyId = $item.PolicyDefinitionId
    $resourceId = $item.ResourceId

    $remediation = Get-AzPolicyRemediation | Where-Object { $_.PolicyDefinitionId -eq $policyId } | Select-Object -First 1

    if ($remediation) {
        Write-Host "Remediating: $($item.PolicyDefinitionName) on $resourceId" -ForegroundColor Yellow
        if (-not $WhatIf) {
            try {
                Start-AzPolicyRemediation -Name "AutoRemediation-$(Get-Date -Format 'yyyyMMdd')" `
                                          -PolicyAssignmentId $item.PolicyAssignmentId `
                                          -ResourceId $resourceId -ErrorAction Stop
                Write-Host "  ✓ Remediation started" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Failed" -ForegroundColor Red
            }
        } else {
            Write-Host "  [WhatIf] Would start remediation" -ForegroundColor Gray
        }
    }
}
Write-Host "Policy remediation scan completed." -ForegroundColor Green