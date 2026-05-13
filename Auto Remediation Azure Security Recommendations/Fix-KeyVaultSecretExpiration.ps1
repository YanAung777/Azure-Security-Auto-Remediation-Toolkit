<#
.SYNOPSIS
    Auto-fix: "Key Vault secrets should have an expiration date"
#>

param(
    [switch]$WhatIf,
    [int]$DefaultExpirationDays = 90
)

Write-Host "=== Setting Expiration Dates on Key Vault Secrets ===" -ForegroundColor Cyan

$keyVaults = Get-AzKeyVault

foreach ($kv in $keyVaults) {
    $secrets = Get-AzKeyVaultSecret -VaultName $kv.VaultName
    
    foreach ($secret in $secrets) {
        if (-not $secret.Attributes.Expires) {
            $name = $secret.Name
            $newExpiry = (Get-Date).AddDays($DefaultExpirationDays)
            
            Write-Host "Secret '$name' in '$($kv.VaultName)' - Setting expiration" -ForegroundColor Yellow
            
            if (-not $WhatIf) {
                try {
                    $value = (Get-AzKeyVaultSecret -VaultName $kv.VaultName -Name $name).SecretValue
                    Set-AzKeyVaultSecret -VaultName $kv.VaultName -Name $name -SecretValue $value -Expires $newExpiry | Out-Null
                    Write-Host "  ✓ Expiration set" -ForegroundColor Green
                } catch {
                    Write-Host "  ✗ Failed" -ForegroundColor Red
                }
            } else {
                Write-Host "  [WhatIf] Would set expiration for '$name'" -ForegroundColor Gray
            }
        }
    }
}
Write-Host "Key Vault Secret Expiration remediation completed." -ForegroundColor Green