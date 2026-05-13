<#
.SYNOPSIS
    Auto-fix: "Key vaults should have soft delete enabled"
#>

param(
    [switch]$WhatIf,
    [int]$SoftDeleteRetentionDays = 90
)

Write-Host "=== Enabling Soft Delete on Key Vaults ===" -ForegroundColor Cyan

$keyVaults = Get-AzKeyVault

foreach ($kv in $keyVaults) {
    $name = $kv.VaultName
    $rg = $kv.ResourceGroupName

    if (-not $kv.EnableSoftDelete) {
        Write-Host "Key Vault '$name' - Enabling Soft Delete" -ForegroundColor Yellow
        
        if (-not $WhatIf) {
            try {
                Update-AzKeyVault -ResourceGroupName $rg `
                                  -VaultName $name `
                                  -EnableSoftDelete $true `
                                  -SoftDeleteRetentionInDays $SoftDeleteRetentionDays `
                                  -ErrorAction Stop
                Write-Host "  ✓ Enabled" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "  [WhatIf] Would enable Soft Delete for '$name'" -ForegroundColor Gray
        }
    }
}
Write-Host "Key Vault Soft Delete remediation completed." -ForegroundColor Green