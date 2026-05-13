<#
.SYNOPSIS
    Auto-fix: "Key vaults should have deletion protection enabled"
#>

param(
    [switch]$WhatIf,
    [int]$SoftDeleteRetentionDays = 90
)

Write-Host "=== Enabling Purge Protection on Key Vaults ===" -ForegroundColor Cyan

$keyVaults = Get-AzKeyVault

foreach ($kv in $keyVaults) {
    $name = $kv.VaultName
    $rg = $kv.ResourceGroupName

    if (-not $kv.EnablePurgeProtection) {
        Write-Host "Key Vault '$name' - Enabling Purge Protection" -ForegroundColor Yellow
        
        if (-not $WhatIf) {
            try {
                Update-AzKeyVault -ResourceGroupName $rg `
                                  -VaultName $name `
                                  -EnableSoftDelete $true `
                                  -SoftDeleteRetentionInDays $SoftDeleteRetentionDays `
                                  -EnablePurgeProtection $true `
                                  -ErrorAction Stop
                Write-Host "  ✓ Enabled Purge Protection" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
            }
        } else {
            Write-Host "  [WhatIf] Would enable Purge Protection for '$name'" -ForegroundColor Gray
        }
    }
}
Write-Host "Key Vault Purge Protection remediation completed." -ForegroundColor Green