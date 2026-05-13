<#
.SYNOPSIS
    Auto-fix: Enable all major Microsoft Defender security plans across all subscriptions
#>

param([switch]$WhatIf)

Write-Host "=== Enabling Microsoft Defender Security Plans (All Subscriptions) ===" -ForegroundColor Cyan

try {
    $subscriptions = Get-AzSubscription -ErrorAction Stop
    Write-Host "Found $($subscriptions.Count) subscription(s)" -ForegroundColor Yellow
} catch {
    Write-Host "  ✗ Failed to retrieve subscriptions" -ForegroundColor Red
    exit 1
}

$plans = @(
    "VirtualMachines",           # Microsoft Defender for Servers
    "StorageAccounts",           # Microsoft Defender for Storage
    "AppServices",               # Microsoft Defender for App Service
    "SqlServers",                # Microsoft Defender for SQL
    "ContainerRegistry",         # Microsoft Defender for Containers
    "KeyVaults",                 # Microsoft Defender for Key Vault
    "Arm",                       # Microsoft Defender for Resource Manager
    "CSPM",                      # Microsoft Defender CSPM
    "Apis"                       # Microsoft Defender for APIs
)

foreach ($subscription in $subscriptions) {
    Write-Host ""
    Write-Host "Processing subscription: $($subscription.Name) ($($subscription.Id))" -ForegroundColor Cyan
    
    try {
        Set-AzContext -SubscriptionId $subscription.Id -ErrorAction Stop | Out-Null
        
        foreach ($plan in $plans) {
            Write-Host "  Enabling plan: $plan" -ForegroundColor Yellow
            
            if (-not $WhatIf) {
                try {
                    Set-AzSecurityPricing -Name $plan -PricingTier "Standard" -ErrorAction Stop
                    Write-Host "    ✓ Enabled" -ForegroundColor Green
                } catch {
                    Write-Host "    ✗ Failed for $plan : $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "    [WhatIf] Would enable $plan" -ForegroundColor Gray
            }
        }
    } catch {
        Write-Host "  ✗ Failed to set context for subscription: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Completed ===" -ForegroundColor Cyan