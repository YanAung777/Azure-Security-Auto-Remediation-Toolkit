<#
.SYNOPSIS
    Auto-fix: "Auditing should be enabled at the server level for SQL Servers"
#>

param(
    [switch]$WhatIf,
    [string]$StorageAccountResourceId = ""
)

Write-Host "=== Enabling SQL Server Auditing ===" -ForegroundColor Cyan

$sqlServers = Get-AzSqlServer

foreach ($server in $sqlServers) {
    $rg = $server.ResourceGroupName
    $name = $server.ServerName

    $audit = Get-AzSqlServerAuditing -ResourceGroupName $rg -ServerName $name -ErrorAction SilentlyContinue
    if (-not $audit -or $audit.State -ne "Enabled") {
        Write-Host "SQL Server '$name' - Enabling Auditing" -ForegroundColor Yellow
        if (-not $WhatIf) {
            $params = @{
                ResourceGroupName = $rg
                ServerName = $name
                State = "Enabled"
            }
            if ($StorageAccountResourceId) { $params.StorageAccountResourceId = $StorageAccountResourceId }
            Set-AzSqlServerAuditing @params -ErrorAction SilentlyContinue
            Write-Host "  ✓ Enabled" -ForegroundColor Green
        } else {
            Write-Host "  [WhatIf] Would enable auditing" -ForegroundColor Gray
        }
    }
}
Write-Host "SQL Server Auditing remediation completed." -ForegroundColor Green