<#
.SYNOPSIS
    Auto-fix: "Guest accounts with write permissions on Azure resources should be removed"
#>

param([switch]$WhatIf)

Write-Host "=== Removing Guest Accounts with Write Permissions ===" -ForegroundColor Cyan

$roles = @("Contributor", "Storage Account Contributor", "Storage Blob Data Contributor")

$assignments = Get-AzRoleAssignment | Where-Object { $_.SignInName -like "*#EXT#*" -and $_.RoleDefinitionName -in $roles }

foreach ($ra in $assignments) {
    Write-Host "Guest '$($ra.SignInName)' has $($ra.RoleDefinitionName)" -ForegroundColor Yellow
    if (-not $WhatIf) {
        Remove-AzRoleAssignment -ObjectId $ra.ObjectId -RoleDefinitionName $ra.RoleDefinitionName -Scope $ra.Scope -ErrorAction SilentlyContinue
        Write-Host "  ✓ Removed" -ForegroundColor Green
    } else {
        Write-Host "  [WhatIf] Would remove" -ForegroundColor Gray
    }
}
Write-Host "Guest Write remediation completed." -ForegroundColor Green