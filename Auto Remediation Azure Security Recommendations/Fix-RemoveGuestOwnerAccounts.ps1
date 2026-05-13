<#
.SYNOPSIS
    Auto-fix: "Guest accounts with owner permissions on Azure resources should be removed"
#>

param([switch]$WhatIf)

Write-Host "=== Removing Guest Accounts with Owner Permissions ===" -ForegroundColor Cyan

$assignments = Get-AzRoleAssignment | Where-Object { $_.RoleDefinitionName -eq "Owner" -and $_.SignInName -like "*#EXT#*" }

foreach ($ra in $assignments) {
    Write-Host "Guest '$($ra.SignInName)' has Owner at $($ra.Scope)" -ForegroundColor Yellow
    if (-not $WhatIf) {
        Remove-AzRoleAssignment -ObjectId $ra.ObjectId -RoleDefinitionName "Owner" -Scope $ra.Scope -ErrorAction SilentlyContinue
        Write-Host "  ✓ Removed" -ForegroundColor Green
    } else {
        Write-Host "  [WhatIf] Would remove" -ForegroundColor Gray
    }
}
Write-Host "Guest Owner remediation completed." -ForegroundColor Green