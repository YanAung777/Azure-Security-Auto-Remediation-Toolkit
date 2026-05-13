<#
.SYNOPSIS
    Auto-fix: "TLS should be updated to the latest version for web apps"
    Sets the Minimum TLS Version to 1.2 (or 1.3) on all Azure Web Apps.

    # Dry run first (recommended)
.\Fix-WebAppMinimumTLS.ps1 -WhatIf

# Actual remediation - Set to TLS 1.2
.\Fix-WebAppMinimumTLS.ps1

# Set to TLS 1.3 (more secure)
.\Fix-WebAppMinimumTLS.ps1 -MinimumTlsVersion "1.3"
#>

param(
    [switch]$WhatIf,
    [string]$MinimumTlsVersion = "1.2"   # Options: "1.2" or "1.3"
)

Write-Host "=== Setting Minimum TLS Version on Azure Web Apps ===" -ForegroundColor Cyan
Write-Host "Target Minimum TLS Version: $MinimumTlsVersion`n" -ForegroundColor Yellow

$webApps = Get-AzWebApp

$fixedCount = 0

foreach ($app in $webApps) {
    $rg = $app.ResourceGroupName
    $name = $app.Name

    try {
        $config = Get-AzWebApp -ResourceGroupName $rg -Name $name -ErrorAction SilentlyContinue

        # Current TLS version (null or older version)
        $currentTls = $config.SiteConfig.MinTlsVersion

        if ($currentTls -ne $MinimumTlsVersion) {
            Write-Host "Web App '$name' - Current TLS: $currentTls → Setting to $MinimumTlsVersion" -ForegroundColor Yellow

            if (-not $WhatIf) {
                Set-AzWebApp -ResourceGroupName $rg `
                             -Name $name `
                             -MinTlsVersion $MinimumTlsVersion `
                             -ErrorAction Stop

                Write-Host "  ✓ Minimum TLS Version $MinimumTlsVersion enabled for '$name'" -ForegroundColor Green
                $fixedCount++
            } else {
                Write-Host "  [WhatIf] Would set Minimum TLS to $MinimumTlsVersion for '$name'" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "  ✗ Failed to update Web App '$name': $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nWeb Apps Minimum TLS remediation completed." -ForegroundColor Green
Write-Host "Updated $fixedCount Web Apps." -ForegroundColor Green