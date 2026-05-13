<#
.SYNOPSIS
    Auto-fix: "Privileged roles should not have permanent access at the subscription and resource group level"
    Detects and helps remediate permanent Owner / Contributor / User Access Administrator assignments.

    # Dry run first (highly recommended)
.\Fix-PrivilegedPermanentAccess.ps1 -WhatIf

# Actual remediation
.\Fix-PrivilegedPermanentAccess.ps1
#>

param(
    [switch]$WhatIf
)

Write-Host "=== Removing / Converting Permanent Privileged Role Assignments at Subscription & RG Level ===" -ForegroundColor Cyan

$highRiskRoles = @("Owner", "Contributor", "User Access Administrator")

$permanentAssignments = Get-AzRoleAssignment | Where-Object {
    $_.RoleDefinitionName -in $highRiskRoles -and 
    ($_.Scope -like "/subscriptions/*" -or $_.Scope -like "/subscriptions/*/resourceGroups/*")
}

if ($permanentAssignments.Count -eq 0) {
    Write-Host "No permanent high-privilege assignments found at Subscription or RG level. Good!" -ForegroundColor Green
    return
}

Write-Host "Found $($permanentAssignments.Count) permanent privileged assignments.`n" -ForegroundColor Yellow

foreach ($assignment in $permanentAssignments) {
    $role   = $assignment.RoleDefinitionName
    $scope  = $assignment.Scope
    $objId  = $assignment.ObjectId
    $objType = $assignment.ObjectType

    Write-Host "Permanent '$role' assignment found → Scope: $scope (PrincipalType: $objType)" -ForegroundColor Yellow

    if (-not $WhatIf) {
        try {
            # Remove the permanent assignment
            Remove-AzRoleAssignment -ObjectId $objId `
                                    -RoleDefinitionName $role `
                                    -Scope $scope -ErrorAction Stop

            Write-Host "  ✓ Removed permanent assignment. Recommend creating Eligible assignment via PIM." -ForegroundColor Green
        }
        catch {
            Write-Host "  ✗ Failed to remove: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [WhatIf] Would remove permanent '$role' at $scope" -ForegroundColor Gray
    }
}

Write-Host "`nPermanent privileged access remediation completed." -ForegroundColor Green
Write-Host "Recommendation: Use Privileged Identity Management (PIM) for eligible (just-in-time) access instead of permanent assignments." -ForegroundColor Cyan