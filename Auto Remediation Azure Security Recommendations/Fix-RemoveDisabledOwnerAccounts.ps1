<#
.SYNOPSIS
    Auto-fix: "Disabled accounts with owner permissions on Azure resources should be removed"
#>

param([switch]$WhatIf)

Write-Host "=== Removing Disabled Accounts with Owner Permissions ===" -ForegroundColor Cyan

$assignments = Get-AzRoleAssignment | Where-Object { $_.RoleDefinitionName -eq "Owner" }

foreach ($ra in $assignments) {
    if ($ra.ObjectType -eq "User") {
        $user = Get-AzADUser -ObjectId $ra.ObjectId -ErrorAction SilentlyContinue
        if ($user -and $user.AccountEnabled -eq $false) {
            Write-Host "Disabled user '$($user.DisplayName)' has Owner at $($ra.Scope)" -ForegroundColor Yellow
            
            if (-not $WhatIf) {
                try {
                    Remove-AzRoleAssignment -ObjectId $ra.ObjectId -RoleDefinitionName "Owner" -Scope $ra.Scope -ErrorAction Stop
                    Write-Host "  ✓ Removed" -ForegroundColor Green
                } catch {
                    Write-Host "  ✗ Failed" -ForegroundColor Red
                }
            } else {
                Write-Host "  [WhatIf] Would remove Owner from disabled user" -ForegroundColor Gray
            }
        }
    }
}
Write-Host "Disabled Owner accounts remediation completed." -ForegroundColor Green