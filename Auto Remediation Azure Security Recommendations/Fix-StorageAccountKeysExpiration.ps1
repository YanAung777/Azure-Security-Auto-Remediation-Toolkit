<#
.SYNOPSIS
    Auto-fix: "Storage account keys should not be expired"
#>

param(
    [switch]$WhatIf,
    [int]$KeyRotationDays = 90
)

Write-Host "=== Rotating Old Storage Account Keys ===" -ForegroundColor Cyan

$accounts = Get-AzStorageAccount

foreach ($sa in $accounts) {
    $rg = $sa.ResourceGroupName
    $name = $sa.StorageAccountName
    $keys = Get-AzStorageAccountKey -ResourceGroupName $rg -Name $name

    foreach ($key in $keys) {
        if (-not $key.CreationTime -or $key.CreationTime -lt (Get-Date).AddDays(-$KeyRotationDays)) {
            Write-Host "Rotating key $($key.KeyName) for $name" -ForegroundColor Yellow
            if (-not $WhatIf) {
                New-AzStorageAccountKey -ResourceGroupName $rg -Name $name -KeyName $key.KeyName | Out-Null
                Write-Host "  ✓ Rotated" -ForegroundColor Green
            }
        }
    }
}
Write-Host "Storage Key Rotation completed." -ForegroundColor Green