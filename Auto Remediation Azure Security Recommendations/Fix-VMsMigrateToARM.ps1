<#
.SYNOPSIS
    Auto-fix: "Virtual machines should be migrated to new Azure Resource Manager resources"
#>

param([switch]$WhatIf)

Write-Host "=== Checking for Classic (ASM) Virtual Machines ===" -ForegroundColor Cyan

$classicVMs = Get-AzResource -ResourceType "Microsoft.ClassicCompute/virtualMachines" -ErrorAction SilentlyContinue

if ($classicVMs.Count -gt 0) {
    Write-Host "Found $($classicVMs.Count) Classic VMs that need migration to ARM!" -ForegroundColor Red
    $classicVMs | Select-Object Name, ResourceGroupName | Format-Table
} else {
    Write-Host "No Classic VMs found. All VMs are on ARM." -ForegroundColor Green
}