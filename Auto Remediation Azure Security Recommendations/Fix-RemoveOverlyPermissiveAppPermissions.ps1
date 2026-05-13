<#
.SYNOPSIS
    Auto-fix: "Overly permissive permissions should not be configured on Function App, Web App or Logic App"
    Removes Contributor role from Managed Identities assigned to App Services.
    Add to Monthly Automation
    # Dry run first
.\Fix-RemoveOverlyPermissiveAppPermissions.ps1 -WhatIf

# Actual remediation
.\Fix-RemoveOverlyPermissiveAppPermissions.ps1
#>

param(
    [switch]$WhatIf
)

Write-Host "=== Removing Overly Permissive (Contributor) Roles from App Service Managed Identities ===" -ForegroundColor Cyan

# Get all Function Apps, Web Apps, and Logic Apps
$webApps = Get-AzWebApp
$functionApps = Get-AzFunctionApp
$logicApps = Get-AzLogicApp   # May need additional module if not available

$allApps = @($webApps) + @($functionApps)

$fixedCount = 0

foreach ($app in $allApps) {
    $rg = $app.ResourceGroupName
    $name = $app.Name
    $principalId = $app.Identity.PrincipalId

    if (-not $principalId) { continue }   # Skip if no Managed Identity

    # Find Contributor role assignments for this Managed Identity
    $contributorAssignments = Get-AzRoleAssignment -ObjectId $principalId | 
        Where-Object { $_.RoleDefinitionName -eq "Contributor" }

    foreach ($assign in $contributorAssignments) {
        $scope = $assign.Scope

        Write-Host "App '$name' has Contributor role at scope: $scope" -ForegroundColor Yellow

        if (-not $WhatIf) {
            try {
                Remove-AzRoleAssignment -ObjectId $principalId `
                                        -RoleDefinitionName "Contributor" `
                                        -Scope $scope -ErrorAction Stop
                
                Write-Host "  ✓ Removed Contributor role from '$name'" -ForegroundColor Green
                $fixedCount++
            }
            catch {
                Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "  [WhatIf] Would remove Contributor from '$name' at $scope" -ForegroundColor Gray
        }
    }
}

Write-Host "`nOverly permissive permissions remediation completed. Removed $fixedCount Contributor assignments." -ForegroundColor Green
Write-Host "Recommendation: Use least-privilege roles (e.g., Reader, Storage Blob Data Contributor) instead." -ForegroundColor Cyan