<#
.SYNOPSIS
    Auto-fix: Database-level firewall rules should be minimized for SQL Servers
    Removes overly permissive database-level firewall rules (0.0.0.0/0).
#>

param([switch]$WhatIf)

Write-Host "=== Minimizing Database-Level Firewall Rules on SQL Servers ===" -ForegroundColor Cyan

$sqlServers = Get-AzSqlServer

$removedCount = 0

foreach ($server in $sqlServers) {
    $rg = $server.ResourceGroupName
    $serverName = $server.ServerName

    $databases = Get-AzSqlDatabase -ResourceGroupName $rg -ServerName $serverName | Where-Object { $_.DatabaseName -ne "master" }

    foreach ($db in $databases) {
        $dbName = $db.DatabaseName
        $rules = Get-AzSqlDatabaseFirewallRule -ResourceGroupName $rg -ServerName $serverName -DatabaseName $dbName

        foreach ($rule in $rules) {
            if ($rule.FirewallRuleName -ne "AllowAllWindowsAzureIps" -and 
                ($rule.StartIPAddress -eq "0.0.0.0" -or $rule.EndIPAddress -eq "0.0.0.0")) {
                
                Write-Host "Database '$dbName' on '$serverName' has permissive rule '$($rule.FirewallRuleName)'" -ForegroundColor Yellow

                if (-not $WhatIf) {
                    try {
                        Remove-AzSqlDatabaseFirewallRule -ResourceGroupName $rg `
                                                        -ServerName $serverName `
                                                        -DatabaseName $dbName `
                                                        -FirewallRuleName $rule.FirewallRuleName -ErrorAction Stop
                        Write-Host "  ✓ Removed permissive firewall rule" -ForegroundColor Green
                        $removedCount++
                    } catch {
                        Write-Host "  ✗ Failed to remove rule" -ForegroundColor Red
                    }
                } else {
                    Write-Host "  [WhatIf] Would remove rule '$($rule.FirewallRuleName)'" -ForegroundColor Gray
                }
            }
        }
    }
}

Write-Host "`nSQL Database Firewall Rules minimization completed. Removed $removedCount permissive rules." -ForegroundColor Green