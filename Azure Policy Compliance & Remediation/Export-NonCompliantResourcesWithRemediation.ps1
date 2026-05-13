<#
.SYNOPSIS
    Export Non-Compliant Resources with Direct Remediation Links
    Generates a detailed report of all non-compliant resources with clickable remediation links.
    # Basic usage
.\Export-NonCompliantResourcesWithRemediation.ps1

# With Excel output (recommended)
.\Export-NonCompliantResourcesWithRemediation.ps1 -ExportToExcel
#>

param(
    [string]$OutputPath = ".\PolicyComplianceReports",
    [switch]$ExportToExcel
)

Write-Host "=== Non-Compliant Resources with Remediation Links ===" -ForegroundColor Cyan

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFolder = Join-Path $OutputPath $timestamp
New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null

$nonCompliantResources = @()

# Get all non-compliant policy states
$states = Get-AzPolicyState -Filter "ComplianceState eq 'NonCompliant'" -All

foreach ($state in $states) {
    $subscription = Get-AzSubscription -SubscriptionId $state.SubscriptionId -ErrorAction SilentlyContinue
    
    # Build remediation portal link
    $remediationLink = "https://portal.azure.com/#blade/Microsoft_Azure_Policy/PolicyComplianceBlade/resourceId/" + 
                       [uri]::EscapeDataString($state.ResourceId) + 
                       "/policyAssignmentId/" + 
                       [uri]::EscapeDataString($state.PolicyAssignmentId)

    $nonCompliantResources += [PSCustomObject]@{
        SubscriptionName     = $subscription.Name
        SubscriptionId       = $state.SubscriptionId
        ResourceName         = $state.ResourceId.Split('/')[-1]
        ResourceType         = $state.ResourceType
        ResourceId           = $state.ResourceId
        PolicyName           = $state.PolicyDefinitionName
        PolicyAssignmentName = $state.PolicyAssignmentName
        ComplianceState      = $state.ComplianceState
        Timestamp            = $state.Timestamp
        RemediationLink      = $remediationLink
    }
}

# Summary
$totalNonCompliant = $nonCompliantResources.Count
Write-Host "Found $totalNonCompliant non-compliant resources." -ForegroundColor Red

# Export to CSV
$csvPath = Join-Path $reportFolder "NonCompliant_Resources_With_Remediation_$timestamp.csv"
$nonCompliantResources | Export-Csv -Path $csvPath -NoTypeInformation

# Export to Excel (with hyperlink)
if ($ExportToExcel) {
    try {
        $excelPath = Join-Path $reportFolder "NonCompliant_Resources_With_Remediation_$timestamp.xlsx"
        
        $nonCompliantResources | Export-Excel -Path $excelPath `
            -WorksheetName "NonCompliantResources" `
            -AutoSize `
            -TableName "NonCompliant" `
            -TableStyle Medium2

        Write-Host "Excel report with remediation links created." -ForegroundColor Green
    } catch {
        Write-Host "Excel export skipped (ImportExcel module not installed)" -ForegroundColor Yellow
    }
}

# Display Top 10
Write-Host "`nTop 10 Non-Compliant Resources:" -ForegroundColor Yellow
$nonCompliantResources | Select-Object -First 10 | 
    Format-Table SubscriptionName, ResourceName, PolicyName, RemediationLink -Wrap

Write-Host "`nFull report saved to: $reportFolder" -ForegroundColor Green
Write-Host "Tip: Open the CSV/Excel file and click the RemediationLink column to go directly to remediation in Azure Portal." -ForegroundColor Cyan