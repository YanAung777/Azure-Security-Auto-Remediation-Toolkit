<#
.SYNOPSIS
    Auto-fix: "Storage accounts should prevent shared key access"
#>

param([switch]$WhatIf)

Write-Host "=== Disabling Shared Key Access ===" -ForegroundColor Cyan

$accounts = Get-AzStorageAccount | Where-Object { $_.AllowSharedKeyAccess -ne $false }

foreach ($sa in $accounts) {
    $rg = $sa.ResourceGroupName
    $name = $sa.StorageAccountName
    Write-Host "Updating: $name" -ForegroundColor Yellow
    if (-not $WhatIf) {
        Set-AzStorageAccount -ResourceGroupName $rg -Name $name -AllowSharedKeyAccess $false -ErrorAction SilentlyContinue
        Write-Host "  ✓ Disabled Shared Key" -ForegroundColor Green
    } else {
        Write-Host "  [WhatIf] Would disable for $name" -ForegroundColor Gray
    }
}
Write-Host "Shared Key Access remediation completed." -ForegroundColor Green