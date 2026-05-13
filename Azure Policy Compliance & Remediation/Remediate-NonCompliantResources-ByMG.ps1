<#
.SYNOPSIS
    Remediate Non-Compliant Resources with Management Group + Severity Filtering
    Allows targeted remediation at specific Management Groups.

    # 1. Remediate High+ severity under a specific Management Group
.\Remediate-NonCompliantResources-ByMG.ps1 -ManagementGroupId "your-mg-id" -Severity High

# 2. Dry run first
.\Remediate-NonCompliantResources-ByMG.ps1 -ManagementGroupId "your-mg-id" -Severity Critical -WhatIf

# 3. Report only (no remediation)
.\Remediate-NonCompliantResources-ByMG.ps1 -ManagementGroupId "your-mg-id" -Severity All -ExportReportOnly
#>

param(
    [string]$ManagementGroupId = "",           # Required: MG ID or Display Name
    [ValidateSet("Critical", "High", "Medium", "Low", "All")]
    [string]$Severity = "High",
    
    [switch]$WhatIf,
    [int]$Top = 300,
    [switch]$ExportReportOnly
)

Write-Host "=== Management Group + Severity Based Remediation ===" -ForegroundColor Cyan
Write-Host "Management Group : $ManagementGroupId" -ForegroundColor Yellow
Write-Host "Severity Filter  : $Severity" -ForegroundColor Yellow
Write-Host "WhatIf Mode      : $WhatIf`n" -ForegroundColor Gray

# Resolve Management Group
$mg = Get-AzManagementGroup -GroupId $ManagementGroupId -ErrorAction SilentlyContinue
if (-not $mg) {
    Write-Host "Management Group '$ManagementGroupId' not found." -ForegroundColor Red
    return
}

Write-Host "Scanning under Management Group: $($mg.DisplayName) ($($mg.Name))" -ForegroundColor Cyan

# Get non-compliant resources under this Management Group
$nonCompliant = Get-AzPolicyState -ManagementGroupName $mg.Name -Filter "ComplianceState eq 'NonCompliant'" -All |
                Select-Object -First $Top

$enhancedList = @()

foreach ($item in $nonCompliant) {
    # Get severity from policy definition
    try {
        $policyDef = Get-AzPolicyDefinition -Id $item.PolicyDefinitionId -ErrorAction SilentlyContinue
        $severityLevel = $policyDef.Properties.metadata.severity
    } catch {
        $severityLevel = "Unknown"
    }

    $enhancedList += [PSCustomObject]@{
        ManagementGroup   = $mg.DisplayName
        SubscriptionId    = $item.SubscriptionId
        ResourceId        = $item.ResourceId
        ResourceName      = $item.ResourceId.Split('/')[-1]
        PolicyName        = $item.PolicyDefinitionName
        Severity          = $severityLevel
        ComplianceState   = $item.ComplianceState
        PolicyAssignmentId= $item.PolicyAssignmentId
        Timestamp         = $item.Timestamp
    }
}

# Apply Severity Filter
if ($Severity -ne "All") {
    $filtered = $enhancedList | Where-Object { $_.Severity -in @($Severity, "Critical", "High") }
} else {
    $filtered = $enhancedList
}

Write-Host "`nFound $($filtered.Count) non-compliant resources matching criteria." -ForegroundColor Yellow

# Export Report
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportPath = "NonCompliant_MG_$($mg.Name)_Severity_$Severity`_$timestamp.csv"
$filtered | Export-Csv -Path $reportPath -NoTypeInformation
Write-Host "Report exported: $reportPath" -ForegroundColor Green

if ($ExportReportOnly) {
    $filtered | Format-Table ManagementGroup, ResourceName, PolicyName, Severity
    return
}

# ====================== REMEDIATION ======================
$remediated = 0

foreach ($item in $filtered) {
    Write-Host "[$($item.Severity)] Remediating: $($item.PolicyName) → $($item.ResourceName)" -ForegroundColor Cyan

    if (-not $WhatIf) {
        try {
            $remediationName = "AutoRemediation-MG-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

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
        Write-Host "  [WhatIf] Would remediate $($item.ResourceName)" -ForegroundColor Gray
    }
}

Write-Host "`n=== Remediation Summary ===" -ForegroundColor Cyan
Write-Host "Management Group : $($mg.DisplayName)" -ForegroundColor Gray
Write-Host "Severity Filter  : $Severity" -ForegroundColor Gray
Write-Host "Resources Found  : $($filtered.Count)" -ForegroundColor Gray
Write-Host "Remediation Tasks Started : $remediated" -ForegroundColor Green

if ($remediated -gt 0) {
    Write-Host "`nYou can track remediation tasks in Azure Portal → Policy → Remediation" -ForegroundColor Yellow
}