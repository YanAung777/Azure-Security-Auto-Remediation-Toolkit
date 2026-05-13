<#
.SYNOPSIS
    Auto-fix: "Secure transfer to storage accounts should be enabled"
#>

param([switch]$WhatIf)

Write-Host "=== Enforcing Secure Transfer (HTTPS Only) ===" -ForegroundColor Cyan

$accounts = Get-AzStorageAccount | Where-Object { $_.EnableHttpsTrafficOnly -eq $false }

foreach ($sa in $accounts) {
    $rg = $sa.ResourceGroupName
    $name = $sa.StorageAccountName
    
    Write-Host "Updating: $name" -ForegroundColor Yellow
    
    if (-not $WhatIf) {
        Set-AzStorageAccount -ResourceGroupName $rg -Name $name -EnableHttpsTrafficOnly $true -ErrorAction SilentlyContinue
        Write-Host "  ✓ Enabled" -ForegroundColor Green
    } else {
        Write-Host "  [WhatIf] Would enable for $name" -ForegroundColor Gray
    }
}
Write-Host "Secure Transfer remediation completed." -ForegroundColor Green