<#
.SYNOPSIS
    Auto-fix: "Database Encryption Symmetric Keys should use AES algorithm in SQL databases"
    Finds symmetric keys using weak algorithms (e.g., DES, RC2, RC4) and recreates them using AES_256.

    # Dry run first
.\Fix-SQLDatabaseSymmetricKeyAES.ps1 -WhatIf

# With SQL Authentication
.\Fix-SQLDatabaseSymmetricKeyAES.ps1 -SqlAdminUser "sqladmin" -SqlAdminPassword "YourStrongPassword"
#>

param(
    [switch]$WhatIf,
    [string]$SqlAdminUser = "",      # Optional: SQL Authentication username
    [string]$SqlAdminPassword = ""   # Optional: SQL Authentication password (use with caution)
)

Write-Host "=== Fixing Symmetric Keys to Use AES Algorithm in SQL Databases ===" -ForegroundColor Cyan

# Get all SQL Servers and their databases
$sqlServers = Get-AzSqlServer

$fixedCount = 0

foreach ($server in $sqlServers) {
    $rg = $server.ResourceGroupName
    $serverName = $server.ServerName

    $databases = Get-AzSqlDatabase -ResourceGroupName $rg -ServerName $serverName | 
                 Where-Object { $_.DatabaseName -ne "master" -and $_.Status -eq "Online" }

    foreach ($db in $databases) {
        $dbName = $db.DatabaseName

        Write-Host "Checking Database: $serverName/$dbName" -ForegroundColor Cyan

        try {
            # Build connection string
            $connStr = "Server=tcp:$serverName.database.windows.net,1433;Initial Catalog=$dbName;Persist Security Info=False;MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

            if ($SqlAdminUser -and $SqlAdminPassword) {
                $connStr += "User ID=$SqlAdminUser;Password=$SqlAdminPassword;"
            } else {
                # Try with Entra ID (Microsoft Entra authentication)
                $connStr += "Authentication=Active Directory Integrated;"
            }

            # Find symmetric keys using weak algorithms
            $query = @"
SELECT name, algorithm_desc 
FROM sys.symmetric_keys 
WHERE algorithm_desc NOT IN ('AES_256', 'AES_192', 'AES_128')
AND name NOT LIKE '##%'
"@

            $weakKeys = Invoke-Sqlcmd -ConnectionString $connStr -Query $query -ErrorAction SilentlyContinue

            foreach ($key in $weakKeys) {
                $keyName = $key.name
                Write-Host "  Weak symmetric key found: '$keyName' ($($key.algorithm_desc)) → Recreating with AES_256" -ForegroundColor Yellow

                if (-not $WhatIf) {
                    $fixQuery = @"
IF EXISTS (SELECT * FROM sys.symmetric_keys WHERE name = '$keyName')
BEGIN
    DROP SYMMETRIC KEY [$keyName];
    CREATE SYMMETRIC KEY [$keyName] 
    WITH ALGORITHM = AES_256 
    ENCRYPTION BY PASSWORD = 'AutoRemediated_Key_$(Get-Date -Format 'yyyyMMdd')';
    PRINT 'Recreated $keyName with AES_256';
END
"@

                    Invoke-Sqlcmd -ConnectionString $connStr -Query $fixQuery | Out-Null
                    Write-Host "  ✓ Recreated '$keyName' using AES_256" -ForegroundColor Green
                    $fixedCount++
                } else {
                    Write-Host "  [WhatIf] Would recreate '$keyName' with AES_256" -ForegroundColor Gray
                }
            }
        }
        catch {
            Write-Host "  ✗ Could not connect to or update database '$dbName': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`nSymmetric Key AES remediation completed." -ForegroundColor Green
Write-Host "Recreated $fixedCount weak symmetric keys." -ForegroundColor Green
Write-Host "Note: New keys are protected by a password. Consider using certificates for production." -ForegroundColor Cyan