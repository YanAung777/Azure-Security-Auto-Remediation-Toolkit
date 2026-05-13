<#
.SYNOPSIS
    Auto-fix: "Role-Based Access Control should be used on Azure Keyvault Services (AKV)"
#>

param([switch]$WhatIf)

Write-Host "=== Enabling Azure RBAC on Key Vaults ===" -ForegroundColor Cyan

$keyVaults = Get-AzKeyVault

foreach ($kv in $keyVaults) {
    $name = $kv.VaultName
    $rg = $kv.ResourceGroupName

    if (-not $kv.EnableRbacAuthorization) {
        Write-Host "Key Vault '$name' - Switching to RBAC" -ForegroundColor Yellow
        
        if (-not $WhatIf) {
            try {
                Update-AzKeyVault -ResourceGroupName $rg `
                                  -VaultName $name `
                                  -EnableRbacAuthorization $true `
                                  -ErrorAction Stop
                Write-Host "  ✓ RBAC enabled" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "  [WhatIf] Would enable RBAC for '$name'" -ForegroundColor Gray
        }
    }
}
Write-Host "Key Vault RBAC remediation completed." -ForegroundColor Green