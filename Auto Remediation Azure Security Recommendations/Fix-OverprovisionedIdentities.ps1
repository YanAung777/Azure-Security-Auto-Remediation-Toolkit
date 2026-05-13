<#
.SYNOPSIS
    Auto-fix: "Azure overprovisioned identities should have only the necessary permissions"
    Removes overly broad roles (especially Contributor) from Managed Identities and Service Principals.

    # Dry run first (strongly recommended)
.\Fix-OverprovisionedIdentities.ps1 -WhatIf

# Actual remediation
.\Fix-OverprovisionedIdentities.ps1

You can customize the roles considered "overly broad":
.\Fix-OverprovisionedIdentities.ps1 -OverlyBroadRoles "Contributor","Owner"
#>

param(
    [switch]$WhatIf,
    [string[]]$OverlyBroadRoles = @("Contributor", "Owner", "User Access Administrator")
)

Write-Host "=== Removing Overprovisioned Permissions from Identities ===" -ForegroundColor Cyan

# Get all role assignments
$roleAssignments = Get-AzRoleAssignment | Where-Object { 
    $_.ObjectType -in @("ServicePrincipal", "ManagedIdentity") -and 
    $_.RoleDefinitionName -in $OverlyBroadRoles 
}

if ($roleAssignments.Count -eq 0) {
    Write-Host "No overprovisioned identities with broad roles found. Good!" -ForegroundColor Green
    return
}

Write-Host "Found $($roleAssignments.Count) overprovisioned role assignments.`n" -ForegroundColor Yellow

$removedCount = 0

foreach ($ra in $roleAssignments) {
    $principalId   = $ra.ObjectId
    $roleName      = $ra.RoleDefinitionName
    $scope         = $ra.Scope
    $principalType = $ra.ObjectType

    # Get friendly name
    try {
        if ($principalType -eq "ServicePrincipal") {
            $displayName = (Get-AzADServicePrincipal -ObjectId $principalId).DisplayName
        } else {
            $displayName = "Managed Identity"
        }
    } catch {
        $displayName = "Unknown"
    }

    Write-Host "$principalType '$displayName' has overly broad role '$roleName' at $scope" -ForegroundColor Yellow

    if (-not $WhatIf) {
        try {
            Remove-AzRoleAssignment -ObjectId $principalId `
                                    -RoleDefinitionName $roleName `
                                    -Scope $scope -ErrorAction Stop

            Write-Host "  ✓ Removed '$roleName' from $principalType" -ForegroundColor Green
            $removedCount++
        }
        catch {
            Write-Host "  ✗ Failed to remove assignment: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [WhatIf] Would remove '$roleName' from '$displayName'" -ForegroundColor Gray
    }
}

Write-Host "`nOverprovisioned identities remediation completed." -ForegroundColor Green
Write-Host "Removed $removedCount broad role assignments." -ForegroundColor Green
Write-Host "Recommendation: Replace with least-privilege roles (e.g., specific Resource Provider roles)." -ForegroundColor Cyan