<#
.SYNOPSIS
    Export Azure Policy Compliance Report per Management Group
    Generates a detailed compliance report across all management groups.

    # Basic usage
.\Export-ManagementGroupPolicyCompliance.ps1

# With Excel output (requires ImportExcel module)
.\Export-ManagementGroupPolicyCompliance.ps1 -ExportToExcel
#>

param(
    [string]$OutputPath = ".\PolicyComplianceReports",
    [switch]$ExportToExcel
)

Write-Host "=== Azure Policy Compliance Report - Per Management Group ===" -ForegroundColor Cyan

# Create output folder
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFolder = Join-Path $OutputPath $timestamp
New-Item -ItemType Directory -Path $reportFolder -Force | Out-Null

$mgCompliance = @()

# Get all Management Groups
$managementGroups = Get-AzManagementGroup -Recurse

foreach ($mg in $managementGroups) {
    $mgId = $mg.Name
    $mgDisplayName = $mg.DisplayName

    Write-Host "Scanning Management Group: $mgDisplayName ($mgId)" -ForegroundColor Yellow

    try {
        # Get policy states for this management group
        $states = Get-AzPolicyState -ManagementGroupName $mgId -All -ErrorAction SilentlyContinue

        if ($states) {
            $summary = $states | Group-Object ComplianceState | ForEach-Object {
                [PSCustomObject]@{
                    ManagementGroupId     = $mgId
                    ManagementGroupName   = $mgDisplayName
                    ComplianceState       = $_.Name
                    ResourceCount         = $_.Count
                    Percentage            = [math]::Round(($_.Count / $states.Count) * 100, 2)
                }
            }

            $mgCompliance += $summary

            # Export detailed report for this MG
            $detailReport = $states | Select-Object `
                @{Name='ManagementGroup'; Expression={$mgDisplayName}},
                PolicyDefinitionName,
                PolicyAssignmentName,
                ComplianceState,
                ResourceId,
                ResourceType,
                Timestamp

            $detailReport | Export-Csv -Path (Join-Path $reportFolder "$mgDisplayName`_Compliance_$timestamp.csv") -NoTypeInformation
        }
    }
    catch {
        Write-Host "  ⚠ Could not retrieve data for $mgDisplayName" -ForegroundColor Yellow
    }
}

# Overall Summary
Write-Host "`n=== Overall Compliance Summary Across Management Groups ===" -ForegroundColor Cyan
$mgCompliance | Format-Table -AutoSize ManagementGroupName, ComplianceState, ResourceCount, Percentage

# Export combined summary
$mgCompliance | Export-Csv -Path (Join-Path $reportFolder "ManagementGroup_PolicyCompliance_Summary_$timestamp.csv") -NoTypeInformation

if ($ExportToExcel) {
    try {
        $mgCompliance | Export-Excel -Path (Join-Path $reportFolder "ManagementGroup_PolicyCompliance_$timestamp.xlsx") `
                     -WorksheetName "ComplianceSummary" -AutoSize -TableName "MGCompliance"
        Write-Host "Excel report generated." -ForegroundColor Green
    } catch {
        Write-Host "Excel export skipped (ImportExcel module not available)" -ForegroundColor Yellow
    }
}

Write-Host "`nReports exported to: $reportFolder" -ForegroundColor Green
Write-Host "Files generated successfully." -ForegroundColor Cyan