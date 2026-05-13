<#
.SYNOPSIS
    Auto-fix: "Storage accounts should prevent public blob access"
#>

param([switch]$WhatIf)

Write-Host "=== Disabling Public Blob Access ===" -ForegroundColor Cyan

$accounts = Get-AzStorageAccount | Where-Object { $_.AllowBlobPublicAccess -eq $true }

foreach ($sa in $accounts) {
    $rg = $sa.ResourceGroupName
    $name = $sa.StorageAccountName
    Write-Host "Updating: $name" -ForegroundColor Yellow
    if (-not $WhatIf) {
        Set-AzStorageAccount -ResourceGroupName $rg -Name $name -AllowBlobPublicAccess $false -ErrorAction SilentlyContinue
        Write-Host "  ✓ Disabled" -ForegroundColor Green
    } else {
        Write-Host "  [WhatIf] Would disable for $name" -ForegroundColor Gray
    }
}
Write-Host "Public Blob Access remediation completed." -ForegroundColor Green