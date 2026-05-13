<#
.SYNOPSIS
    Auto-fix: "Restricted network access should be configured on Internet exposed Function app"
    Adds a default "Deny All" rule + allows your corporate IP ranges (you must customize the allowed IPs).

    .\Fix-RestrictFunctionAppNetwork.ps1 -WhatIf
    .\Fix-RestrictFunctionAppNetwork.ps1
#>

param(
    [switch]$WhatIf,
    [string[]]$AllowedIPRanges = @("203.0.113.0/24", "198.51.100.0/24")   # ← CHANGE TO YOUR CORPORATE IP RANGES
)

Write-Host "=== Restricting Network Access on Internet-Exposed Function Apps ===" -ForegroundColor Cyan

if ($AllowedIPRanges.Count -eq 0) {
    Write-Host "WARNING: No AllowedIPRanges provided. Please edit the script with your corporate IPs." -ForegroundColor Red
    return
}

$functionApps = Get-AzFunctionApp

$fixedCount = 0

foreach ($app in $functionApps) {
    $rg = $app.ResourceGroupName
    $name = $app.Name

    try {
        # Get current access restrictions
        $restrictions = Get-AzWebAppAccessRestrictionConfig -ResourceGroupName $rg -Name $name
        
        # If no restrictions or only Allow All, apply fix
        if (-not $restrictions.MainSiteAccessRestrictionRules -or 
            ($restrictions.MainSiteAccessRestrictionRules | Where-Object { $_.Action -eq "Allow" -and $_.IpAddress -eq "0.0.0.0/0" })) {
            
            Write-Host "Function App '$name' is internet-exposed. Applying network restrictions..." -ForegroundColor Yellow

            if (-not $WhatIf) {
                # Add Deny All rule (lowest priority)
                Add-AzWebAppAccessRestrictionRule -ResourceGroupName $rg `
                                                  -WebAppName $name `
                                                  -Name "DenyAll" `
                                                  -Priority 1000 `
                                                  -Action Deny `
                                                  -IpAddress "0.0.0.0/0" `
                                                  -ErrorAction Stop

                # Add your allowed IP ranges (higher priority)
                $priority = 100
                foreach ($ip in $AllowedIPRanges) {
                    Add-AzWebAppAccessRestrictionRule -ResourceGroupName $rg `
                                                      -WebAppName $name `
                                                      -Name "AllowCorporate" `
                                                      -Priority $priority `
                                                      -Action Allow `
                                                      -IpAddress $ip `
                                                      -ErrorAction Stop
                    $priority += 10
                }

                Write-Host "  ✓ Network restrictions applied to '$name'" -ForegroundColor Green
                $fixedCount++
            } else {
                Write-Host "  [WhatIf] Would restrict network access for '$name'" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "  ✗ Failed to update Function App '$name': $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nFunction App Network Restriction remediation completed. Updated $fixedCount Function Apps." -ForegroundColor Green
Write-Host "Important: Update the `$AllowedIPRanges` array with your actual corporate/public IP ranges." -ForegroundColor Yellow