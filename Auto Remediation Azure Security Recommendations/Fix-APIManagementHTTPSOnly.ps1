<#
.SYNOPSIS
    Auto-fix: "API Management APIs should use only encrypted protocols"
#>

param([switch]$WhatIf)

Write-Host "=== Enforcing HTTPS Only on API Management APIs ===" -ForegroundColor Cyan

$apimServices = Get-AzApiManagement

foreach ($apim in $apimServices) {
    $rg = $apim.ResourceGroupName
    $serviceName = $apim.Name
    $apis = Get-AzApiManagementApi -ResourceGroupName $rg -ServiceName $serviceName

    foreach ($api in $apis) {
        if ($api.Protocols -contains "Http") {
            Write-Host "API '$($api.DisplayName)' - Enforcing HTTPS Only" -ForegroundColor Yellow
            if (-not $WhatIf) {
                try {
                    Set-AzApiManagementApi -ResourceGroupName $rg `
                                          -ServiceName $serviceName `
                                          -ApiId $api.ApiId `
                                          -Protocols @("Https") -ErrorAction Stop
                    Write-Host "  ✓ HTTPS Only enforced" -ForegroundColor Green
                } catch {
                    Write-Host "  ✗ Failed" -ForegroundColor Red
                }
            } else {
                Write-Host "  [WhatIf] Would enforce HTTPS Only" -ForegroundColor Gray
            }
        }
    }
}
Write-Host "API Management HTTPS Only remediation completed." -ForegroundColor Green