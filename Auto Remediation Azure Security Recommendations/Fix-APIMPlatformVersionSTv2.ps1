<#
.SYNOPSIS
    Auto-fix: "Azure API Management platform version should be stv2"
#>

param([switch]$WhatIf)

Write-Host "=== Upgrading API Management to STv2 ===" -ForegroundColor Cyan

$apimServices = Get-AzApiManagement

foreach ($apim in $apimServices) {
    if ($apim.PlatformVersion -ne "stv2") {
        Write-Host "API Management '$($apim.Name)' - Upgrading to STv2" -ForegroundColor Yellow
        if (-not $WhatIf) {
            try {
                Set-AzApiManagement -ResourceGroupName $apim.ResourceGroupName `
                                    -Name $apim.Name `
                                    -PlatformVersion "stv2" -ErrorAction Stop
                Write-Host "  ✓ Upgraded to STv2" -ForegroundColor Green
            } catch {
                Write-Host "  ✗ Failed (may require manual migration)" -ForegroundColor Red
            }
        } else {
            Write-Host "  [WhatIf] Would upgrade to STv2" -ForegroundColor Gray
        }
    }
}
Write-Host "API Management STv2 upgrade completed." -ForegroundColor Green