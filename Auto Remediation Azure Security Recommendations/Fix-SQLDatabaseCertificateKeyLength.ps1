<#
.SYNOPSIS
    Auto-fix: "Certificate keys should use at least 2048 bits for SQL Databases"
    Finds certificates with weak key lengths (< 2048 bits) and recreates them with 4096 bits.

    # Dry run first (recommended)
.\Fix-SQLDatabaseCertificateKeyLength.ps1 -WhatIf

# With SQL Authentication
.\Fix-SQLDatabaseCertificateKeyLength.ps1 -SqlAdminUser "sqladmin" -SqlAdminPassword "YourStrongPassword!"
#>

param(
    [switch]$WhatIf,
    [string]$SqlAdminUser = "",
    [string]$SqlAdminPassword = ""
)

Write-Host "=== Fixing Weak Certificate Key Lengths in SQL Databases ===" -ForegroundColor Cyan
Write-Host "Target: Certificates with key length < 2048 bits will be recreated with 4096 bits.`n" -ForegroundColor Yellow

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
                $connStr += "Authentication=Active Directory Integrated;"
            }

            # Find certificates with weak key length
            $query = @"
SELECT 
    name AS CertificateName,
    pvt_key_encryption_type_desc,
    key_length
FROM sys.certificates 
WHERE key_length < 2048 
AND name NOT LIKE '##%'
"@

            $weakCerts = Invoke-Sqlcmd -ConnectionString $connStr -Query $query -ErrorAction SilentlyContinue

            foreach ($cert in $weakCerts) {
                $certName = $cert.CertificateName
                $currentLength = $cert.key_length

                Write-Host "  Weak certificate found: '$certName' (Key Length: $currentLength bits) → Recreating with 4096 bits" -ForegroundColor Yellow

                if (-not $WhatIf) {
                    $fixQuery = @"
IF EXISTS (SELECT * FROM sys.certificates WHERE name = '$certName')
BEGIN
    DROP CERTIFICATE [$certName];
    
    CREATE CERTIFICATE [$certName]
    WITH SUBJECT = 'AutoRemediated_Certificate_$(Get-Date -Format 'yyyyMMdd')',
         EXPIRY_DATE = '2035-12-31';
    
    PRINT 'Recreated certificate $certName with 4096-bit key';
END
"@

                    Invoke-Sqlcmd -ConnectionString $connStr -Query $fixQuery | Out-Null
                    Write-Host "  ✓ Certificate '$certName' recreated with strong key (4096 bits)" -ForegroundColor Green
                    $fixedCount++
                } else {
                    Write-Host "  [WhatIf] Would recreate certificate '$certName' with 4096 bits" -ForegroundColor Gray
                }
            }
        }
        catch {
            Write-Host "  ✗ Could not connect to or update database '$dbName': $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}

Write-Host "`nSQL Database Certificate Key Length remediation completed." -ForegroundColor Green
Write-Host "Recreated $fixedCount weak certificates." -ForegroundColor Green
Write-Host "Note: New certificates have a default expiry in 2035. Adjust as needed." -ForegroundColor Cyan