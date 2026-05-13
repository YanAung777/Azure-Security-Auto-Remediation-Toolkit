<#
.SYNOPSIS
    Auto-fix: "require_secure_transport should be set to 'on' for Azure Database for PostgreSQL Servers"
#>

param([switch]$WhatIf)

Write-Host "=== Enforcing require_secure_transport = ON on PostgreSQL Servers ===" -ForegroundColor Cyan

# Flexible Servers
$flexServers = Get-AzResource -ResourceType "Microsoft.DBforPostgreSQL/flexibleServers"
foreach ($s in $flexServers) {
    if (-not $WhatIf) {
        Update-AzPostgreSqlFlexibleServerConfiguration -ResourceGroupName $s.ResourceGroupName `
                                                       -ServerName $s.Name `
                                                       -Name "require_secure_transport" `
                                                       -Value "on" | Out-Null
    }
    Write-Host "  ✓ Flexible Server '$($s.Name)' updated" -ForegroundColor Green
}

Write-Host "PostgreSQL secure transport remediation completed." -ForegroundColor Green