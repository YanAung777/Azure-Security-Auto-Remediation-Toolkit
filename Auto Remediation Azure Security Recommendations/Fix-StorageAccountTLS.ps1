<#
.SYNOPSIS
    Auto-fix: "Storage accounts should have the specified minimum TLS version"
#>

param(
    [switch]$WhatIf,
    [string]$MinimumTlsVersion = "TLS1_2"
)

Write-Host "=== Setting Minimum TLS Version on Storage Accounts ===" -ForegroundColor Cyan

$accounts = Get-AzStorageAccount | Where-Object { $_.MinimumTlsVersion -ne $MinimumTlsVersion }

foreach ($sa in $accounts) {
    $rg = $sa.ResourceGroupName
    $name = $sa.StorageAccountName
    
    Write-Host "Updating: $name → $MinimumTlsVersion" -ForegroundColor Yellow
    
    if (-not $WhatIf) {
        try {
            Set-AzStorageAccount -ResourceGroupName $rg -Name $name -MinimumTlsVersion $MinimumTlsVersion -ErrorAction Stop
            Write-Host "  ✓ Updated" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "  [WhatIf] Would update $name" -ForegroundColor Gray
    }
}
Write-Host "Storage TLS remediation completed." -ForegroundColor Green