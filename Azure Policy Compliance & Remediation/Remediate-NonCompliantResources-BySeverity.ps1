<#
.SYNOPSIS
    Remediate Non-Compliant Resources with Severity Filtering
    Allows you to target only Critical, High, Medium, or Low severity findings.

    # 1. Remediate only Critical and High severity (recommended)
.\Remediate-NonCompliantResources-BySeverity.ps1 -Severity High

# 2. Dry run first
.\Remediate-NonCompliantResources-BySeverity.ps1 -Severity Critical -WhatIf

# 3. Export report only (no remediation)
.\Remediate-NonCompliantResources-BySeverity.ps1 -Severity All -ExportReportOnly
#>

param(
    [ValidateSet("Critical", "High", "Medium", "Low", "All")]
    [string]$Severity = "High",           # Default: High and above
    
    [switch]$WhatIf,
    [int]$Top = 200,                      # Safety limit
    [switch]$ExportReportOnly             # Only export, don't remediate
)

Write-Host "=== Severity-Based Policy Remediation ===" -ForegroundColor Cyan
Write-Host "Target Severity : $Severity" -ForegroundColor Yellow
Write-Host "WhatIf Mode     : $WhatIf`n" -ForegroundColor Gray

# Get non-compliant resources with severity
$nonCompliant = Get-AzPolicyState -Filter "ComplianceState eq 'NonCompliant'" -All |
                Where-Object { $_.PolicyDefinitionName -ne $null } |
                Select-Object -First $Top

# Add severity information (from policy definition or metadata)
$enhancedList = @()

foreach ($item in $nonCompliant) {
    # Get policy definition to extract severity
    try {
        $policyDef = Get-AzPolicyDefinition -Id $item.PolicyDefinitionId -ErrorAction SilentlyContinue
        $severity = $policyDef.Properties.metadata.severity
    } catch {
        $severity = "Unknown"
    }

    $enhancedList += [PSCustomObject]@{
        SubscriptionId     = $item.SubscriptionId
        ResourceId         = $item.ResourceId
        ResourceName       = $item.ResourceId.Split('/')[-1]
        PolicyName         = $item.PolicyDefinitionName
        Severity           = $severity
        ComplianceState    = $item.ComplianceState
        PolicyAssignmentId = $item.PolicyAssignmentId
        Timestamp          = $item.Timestamp
    }
}

# Apply severity filter
if ($Severity -ne "All") {
    $filtered = $enhancedList | Where-Object { $_.Severity -in @($Severity, "Critical", "High") }  # Always include Critical
} else {
    $filtered = $enhancedList
}

Write-Host "Found $($filtered.Count) non-compliant resources matching severity filter.`n" -ForegroundColor Yellow

# Export report
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$filtered | Export-Csv -Path "NonCompliant_Severity_$Severity`_$timestamp.csv" -NoTypeInformation
Write-Host "Report exported: NonCompliant_Severity_$Severity`_$timestamp.csv" -ForegroundColor Green

if ($ExportReportOnly) {
    Write-Host "Report-only mode enabled. No remediation performed." -ForegroundColor Cyan
    $filtered | Format-Table SubscriptionId, ResourceName, PolicyName, Severity
    return
}

# ====================== PERFORM REMEDIATION ======================
$remediated = 0

foreach ($item in $filtered) {
    Write-Host "Remediating [$($item.Severity)] $($item.PolicyName) → $($item.ResourceName)" -ForegroundColor Cyan

    if (-not $WhatIf) {
        try {
            $remediationName = "AutoRemediation-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

            Start-AzPolicyRemediation `
                -Name $remediationName `
                -PolicyAssignmentId $item.PolicyAssignmentId `
                -ResourceId $item.ResourceId | Out-Null

            Write-Host "  ✓ Remediation task started" -ForegroundColor Green
            $remediated++
        }
        catch {
            Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [WhatIf] Would start remediation" -ForegroundColor Gray
    }
}

Write-Host "`n=== Remediation Summary ===" -ForegroundColor Cyan
Write-Host "Severity Filter : $Severity" -ForegroundColor Gray
Write-Host "Resources Found : $($filtered.Count)" -ForegroundColor Gray
Write-Host "Remediation Started : $remediated" -ForegroundColor Green

if ($remediated -gt 0) {
    Write-Host "`nCheck remediation status in Azure Portal → Policy → Remediation" -ForegroundColor Yellow
}