<#
.SYNOPSIS
    Auto-fix: "Disabled accounts with read and write permissions on Azure resources should be removed"
#>

param([switch]$WhatIf)

Write-Host "=== Removing Disabled Accounts with Read/Write Permissions ===" -ForegroundColor Cyan

$roles = @("Contributor", "Reader", "Storage Blob Data Contributor", "Storage Blob Data Reader")

$assignments = Get-AzRoleAssignment | Where-Object { $_.ObjectType -eq "User" -and $_.RoleDefinitionName -in $roles }

foreach ($ra in $assignments) {
    $user = Get-AzADUser -ObjectId $ra.ObjectId -ErrorAction SilentlyContinue
    if ($user -and $user.AccountEnabled -eq $false) {
        Write-Host "Disabled user '$($user.DisplayName)' has $($ra.RoleDefinitionName) at $($ra.Scope)" -ForegroundColor Yellow
        
        if (-not $WhatIf) {
            Remove-AzRoleAssignment -ObjectId $ra.ObjectId -RoleDefinitionName $ra.RoleDefinitionName -Scope $ra.Scope -ErrorAction SilentlyContinue
            Write-Host "  ✓ Removed" -ForegroundColor Green
        } else {
            Write-Host "  [WhatIf] Would remove" -ForegroundColor Gray
        }
    }
}
Write-Host "Disabled Read/Write accounts remediation completed." -ForegroundColor Green