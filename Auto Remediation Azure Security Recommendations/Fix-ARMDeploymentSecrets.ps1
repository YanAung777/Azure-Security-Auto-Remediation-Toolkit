<#
.SYNOPSIS
    Auto-fix: "Azure Resource Manager deployments should have secrets findings resolved"
#>

param([switch]$WhatIf)

Write-Host "=== Scanning ARM Deployments for Hardcoded Secrets ===" -ForegroundColor Cyan

$deployments = Get-AzResourceGroupDeployment -ErrorAction SilentlyContinue | 
               Sort-Object Timestamp -Descending | Select-Object -First 100

$secretCount = 0

foreach ($dep in $deployments) {
    $suspicious = $false
    if ($dep.Parameters -match "(?i)password|secret|key|credential|token|auth") { $suspicious = $true }
    if ($dep.Outputs -match "(?i)password|secret|key|credential|token|auth") { $suspicious = $true }

    if ($suspicious) {
        Write-Host "⚠ Potential secret in deployment: $($dep.DeploymentName) (RG: $($dep.ResourceGroupName))" -ForegroundColor Yellow
        $secretCount++
    }
}

if ($secretCount -eq 0) {
    Write-Host "No obvious hardcoded secrets found in recent deployments." -ForegroundColor Green
} else {
    Write-Host "`n$secretCount deployments may contain secrets. Use Key Vault references instead." -ForegroundColor Cyan
}