<#
.SYNOPSIS
    Master Runner for Azure Policy Compliance & Remediation Toolkit
    Executes all compliance reporting and remediation scripts in logical order.
    
    Version: 1.0

    # 1. Dry run (recommended first)
.\Run-AllPolicyComplianceTools.ps1 -WhatIf

# 2. Full run with High severity remediation
.\Run-AllPolicyComplianceTools.ps1 -Severity High

# 3. Run for specific Management Group
.\Run-AllPolicyComplianceTools.ps1 -ManagementGroupId "your-mg-id" -Severity Critical
#>

param(
    [switch]$WhatIf,
    [switch]$ExportAllReports,
    [string]$ManagementGroupId = "",
    [string]$Severity = "High"
)

Write-Host "=== Azure Policy Compliance Master Runner ===" -ForegroundColor Cyan
Write-Host "Mode: $(if($WhatIf){"WhatIf (Dry Run)"} else {"Live Remediation"})`n" -ForegroundColor Yellow

$results = @()
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# ====================== COMPLIANCE & REMEDIATION WORKFLOW ======================

Write-Host "1. Exporting Management Group Compliance Report..." -ForegroundColor Cyan
try {
    .\Export-ManagementGroupPolicyCompliance.ps1 -ExportToExcel
    $results += [PSCustomObject]@{ Step = "Management Group Compliance Export"; Status = "Success" }
} catch {
    $results += [PSCustomObject]@{ Step = "Management Group Compliance Export"; Status = "Failed" }
}

Write-Host "`n2. Exporting Non-Compliant Resources with Remediation Links..." -ForegroundColor Cyan
try {
    .\Export-NonCompliantResourcesWithRemediation.ps1 -ExportToExcel
    $results += [PSCustomObject]@{ Step = "Non-Compliant Resources Export"; Status = "Success" }
} catch {
    $results += [PSCustomObject]@{ Step = "Non-Compliant Resources Export"; Status = "Failed" }
}

Write-Host "`n3. Running Severity-Based Remediation ($Severity)..." -ForegroundColor Cyan
if ($ManagementGroupId) {
    try {
        .\Remediate-NonCompliantResources-MultipleMGs.ps1 `
            -ManagementGroupIds $ManagementGroupId `
            -Severity $Severity `
            -WhatIf:$WhatIf
        $results += [PSCustomObject]@{ Step = "MG Remediation ($Severity)"; Status = "Success" }
    } catch {
        $results += [PSCustomObject]@{ Step = "MG Remediation ($Severity)"; Status = "Failed" }
    }
} else {
    try {
        .\Remediate-NonCompliantResources-BySeverity.ps1 -Severity $Severity -WhatIf:$WhatIf
        $results += [PSCustomObject]@{ Step = "Severity Remediation ($Severity)"; Status = "Success" }
    } catch {
        $results += [PSCustomObject]@{ Step = "Severity Remediation ($Severity)"; Status = "Failed" }
    }
}

Write-Host "`n4. Running Bulk Policy Assignment (Common Security Policies)..." -ForegroundColor Cyan
try {
    .\Assign-CommonSecurityPolicies.ps1 -WhatIf:$WhatIf
    $results += [PSCustomObject]@{ Step = "Bulk Policy Assignment"; Status = "Success" }
} catch {
    $results += [PSCustomObject]@{ Step = "Bulk Policy Assignment"; Status = "Failed" }
}

# ====================== FINAL SUMMARY ======================
Write-Host "`n" + "="*80 -ForegroundColor Cyan
Write-Host "AZURE POLICY COMPLIANCE MASTER RUN SUMMARY" -ForegroundColor Cyan
Write-Host "="*80 -ForegroundColor Cyan

$results | Format-Table -AutoSize

Write-Host "`nAll compliance and remediation tasks completed!" -ForegroundColor Green
Write-Host "Check the 'PolicyComplianceReports' folder for detailed exports." -ForegroundColor Cyan
Write-Host "`nRecommendation: Review remediation tasks in Azure Portal → Policy → Remediation" -ForegroundColor Yellow