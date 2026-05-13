<#
.SYNOPSIS
    Bulk Remediate Non-Compliant Resources Across Multiple Management Groups
    With Severity filtering and full reporting.

    # Remediate High+ severity across multiple Management Groups
.\Remediate-NonCompliantResources-MultipleMGs.ps1 `
    -ManagementGroupIds "mg-prod", "mg-dev", "mg-staging" `
    -Severity High

# Dry run
.\Remediate-NonCompliantResources-MultipleMGs.ps1 `
    -ManagementGroupIds "mg-prod" `
    -Severity Critical `
    -WhatIf

# Report only (no remediation)
.\Remediate-NonCompliantResources-MultipleMGs.ps1 `
    -ManagementGroupIds "mg-prod", "mg-dev" `
    -Severity All `
    -ExportReportOnly
    
#>

param(
    [string[]]$ManagementGroupIds = @(),     # List of MG IDs or Display Names
    [ValidateSet("Critical", "High", "Medium", "Low", "All")]
    [string]$Severity = "High",
    
    [switch]$WhatIf,
    [int]$TopPerMG = 150,                     # Limit per Management Group
    [switch]$ExportReportOnly
)

Write-Host "=== Multi-Management Group Policy Remediation ===" -ForegroundColor Cyan
Write-Host "Target Severity : $Severity" -ForegroundColor Yellow
Write-Host "WhatIf Mode     : $WhatIf`n" -ForegroundColor Gray

if ($ManagementGroupIds.Count -eq 0) {
    Write-Host "ERROR: Please provide at least one Management Group ID" -ForegroundColor Red
    return
}

$allResults = @()
$totalRemediated = 0

foreach ($mgInput in $ManagementGroupIds) {
    # Resolve Management Group
    $mg = Get-AzManagementGroup -GroupId $mgInput -ErrorAction SilentlyContinue
    if (-not $mg) {
        Write-Host "⚠ Management Group '$mgInput' not found. Skipping..." -ForegroundColor Yellow
        continue
    }

    Write-Host "`nProcessing Management Group: $($mg.DisplayName) ($($mg.Name))" -ForegroundColor Magenta

    # Get non-compliant resources under this MG
    $states = Get-AzPolicyState -ManagementGroupName $mg.Name -Filter "ComplianceState eq 'NonCompliant'" -All |
              Select-Object -First $TopPerMG

    $enhanced = @()

    foreach ($state in $states) {
        try {
            $policyDef = Get-AzPolicyDefinition -Id $state.PolicyDefinitionId -ErrorAction SilentlyContinue
            $sev = $policyDef.Properties.metadata.severity
        } catch {
            $sev = "Unknown"
        }

        $enhanced += [PSCustomObject]@{
            ManagementGroup   = $mg.DisplayName
            SubscriptionId    = $state.SubscriptionId
            ResourceId        = $state.ResourceId
            ResourceName      = $state.ResourceId.Split('/')[-1]
            PolicyName        = $state.PolicyDefinitionName
            Severity          = $sev
            PolicyAssignmentId= $state.PolicyAssignmentId
        }
    }

    # Apply Severity Filter
    if ($Severity -ne "All") {
        $toRemediate = $enhanced | Where-Object { $_.Severity -in @($Severity, "Critical", "High") }
    } else {
        $toRemediate = $enhanced
    }

    Write-Host "  Found $($toRemediate.Count) matching non-compliant resources" -ForegroundColor Yellow

    # Export per MG report
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $toRemediate | Export-Csv -Path "NonCompliant_$($mg.Name)_$Severity`_$timestamp.csv" -NoTypeInformation

    if ($ExportReportOnly) {
        $toRemediate | Format-Table ResourceName, PolicyName, Severity
        continue
    }

    # Perform Remediation
    $mgRemediated = 0
    foreach ($item in $toRemediate) {
        if (-not $WhatIf) {
            try {
                $remediationName = "AutoRemediation-$($mg.Name)-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                
                Start-AzPolicyRemediation `
                    -Name $remediationName `
                    -PolicyAssignmentId $item.PolicyAssignmentId `
                    -ResourceId $item.ResourceId | Out-Null
                
                $mgRemediated++
                $totalRemediated++
                Write-Host "  ✓ Remediation started for $($item.ResourceName)" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Failed for $($item.ResourceName)" -ForegroundColor Red
            }
        } else {
            Write-Host "  [WhatIf] Would remediate $($item.ResourceName)" -ForegroundColor Gray
        }
    }

    $allResults += [PSCustomObject]@{
        ManagementGroup = $mg.DisplayName
        ResourcesFound  = $toRemediate.Count
        Remediated      = $mgRemediated
    }
}

# Final Summary
Write-Host "`n" + "="*70 -ForegroundColor Cyan
Write-Host "MULTI-MANAGEMENT GROUP REMEDIATION SUMMARY" -ForegroundColor Cyan
Write-Host "="*70 -ForegroundColor Cyan

$allResults | Format-Table -AutoSize

Write-Host "`nTotal Remediation Tasks Started: $totalRemediated" -ForegroundColor Green
Write-Host "You can monitor progress in Azure Portal → Policy → Remediation" -ForegroundColor Yellow

if ($ExportReportOnly) {
    Write-Host "Report-only mode completed." -ForegroundColor Cyan
}