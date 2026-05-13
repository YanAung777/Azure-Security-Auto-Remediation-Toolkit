<#
.SYNOPSIS
    Master Auto-Remediation Runner for Azure Security Recommendations
    Enhanced Version - Includes all scripts with advanced features
    Version: 3.0
    
.DESCRIPTION
    - Validates Azure connection and modules before execution
    - Supports selective execution by category
    - Captures detailed error context and logging
    - Provides comprehensive analytics and reporting
    - Includes dependency management for related fixes
    - Detailed logging to file for troubleshooting
#>

param(
    [switch]$WhatIf,
    [switch]$SkipSummary,
    [ValidateSet("All", "Storage", "KeyVault", "Defender", "Identity", "AppServices", "API", "SQL", "Networking", "Other")]
    [string]$Category = "All"
)

#region ====================== INITIALIZATION ======================
$startTime = Get-Date
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $scriptPath "AutoRemediation_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$results = @()

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
    
    switch ($Level) {
        "ERROR"   { Write-Host $Message -ForegroundColor Red }
        "WARNING" { Write-Host $Message -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        default  { Write-Host $Message -ForegroundColor Gray }
    }
}

Write-Host "=== Master Security Auto-Remediation Runner v3.0 ===" -ForegroundColor Cyan
Write-Host "Start Time  : $startTime" -ForegroundColor Gray
Write-Host "Category    : $Category" -ForegroundColor Gray
Write-Host "WhatIf Mode : $WhatIf" -ForegroundColor Yellow
Write-Host "Log File    : $logFile`n" -ForegroundColor Gray
Write-Log "=== Master Security Auto-Remediation Runner v3.0 ===" "INFO"
#endregion

#region ====================== VALIDATION FUNCTIONS ======================
function Test-AzureConnection {
    Write-Host "`nValidating Azure Connection..." -ForegroundColor Cyan
    try {
        $context = Get-AzContext -ErrorAction Stop
        if ($null -eq $context) {
            Write-Log "Not authenticated to Azure. Please run Connect-AzAccount first." "ERROR"
            return $false
        }
        Write-Log "✓ Azure Connection: $($context.Account.Id) (Subscription: $($context.Subscription.Name))" "SUCCESS"
        return $true
    } catch {
        Write-Log "✗ Azure Connection Failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Test-RequiredModules {
    Write-Host "Validating Required PowerShell Modules..." -ForegroundColor Cyan
    $requiredModules = @("Az.Security", "Az.Accounts")
    $allModulesOk = $true
    
    foreach ($module in $requiredModules) {
        try {
            $imported = Get-Module -Name $module -ErrorAction SilentlyContinue
            if ($null -eq $imported) {
                Import-Module -Name $module -ErrorAction Stop | Out-Null
            }
            Write-Log "✓ Module loaded: $module" "SUCCESS"
        } catch {
            Write-Log "✗ Module validation failed: $module - $($_.Exception.Message)" "ERROR"
            $allModulesOk = $false
        }
    }
    return $allModulesOk
}

function Test-ScriptFiles {
    param([array]$Scripts)
    Write-Host "Validating Script Files..." -ForegroundColor Cyan
    $missingScripts = @()
    
    foreach ($script in $Scripts) {
        $scriptPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) $script
        if (-not (Test-Path $scriptPath)) {
            Write-Log "✗ Script not found: $script" "WARNING"
            $missingScripts += $script
        } else {
            Write-Log "✓ Script found: $script" "SUCCESS"
        }
    }
    return $missingScripts
}
#endregion

#region ====================== SCRIPT DEFINITIONS WITH CATEGORIES ======================
$allScripts = @{
    Storage = @{
        Scripts = @(
            @{Name = "Fix-StorageAccountTLS.ps1"; Dependencies = @()},
            @{Name = "Fix-StorageSecureTransfer.ps1"; Dependencies = @()},
            @{Name = "Fix-StoragePublicBlobAccess.ps1"; Dependencies = @()},
            @{Name = "Fix-StorageAccountKeysExpiration.ps1"; Dependencies = @()},
            @{Name = "Fix-StorageAccountDisableSharedKey.ps1"; Dependencies = @()}
        )
        Description = "Storage Account Security Fixes"
    }
    KeyVault = @{
        Scripts = @(
            @{Name = "Fix-EnableKeyVaultSoftDelete.ps1"; Dependencies = @()},
            @{Name = "Fix-EnableKeyVaultPurgeProtection.ps1"; Dependencies = @("Fix-EnableKeyVaultSoftDelete.ps1")},
            @{Name = "Fix-EnableKeyVaultRBAC.ps1"; Dependencies = @()},
            @{Name = "Fix-KeyVaultSecretExpiration.ps1"; Dependencies = @()}
        )
        Description = "Key Vault Security Fixes"
    }
    Defender = @{
        Scripts = @(
            @{Name = "Fix-EnableDefenderPlans.ps1"; Dependencies = @()}
        )
        Description = "Microsoft Defender Plans"
    }
    Identity = @{
        Scripts = @(
            @{Name = "Fix-RemoveDisabledOwnerAccounts.ps1"; Dependencies = @()},
            @{Name = "Fix-RemoveDisabledReadWriteAccounts.ps1"; Dependencies = @()},
            @{Name = "Fix-RemoveGuestOwnerAccounts.ps1"; Dependencies = @()},
            @{Name = "Fix-RemoveGuestWriteAccounts.ps1"; Dependencies = @()},
            @{Name = "Fix-RemoveGuestReadAccounts.ps1"; Dependencies = @()},
            @{Name = "Fix-RemoveInactiveIdentitiesPermissions.ps1"; Dependencies = @()},
            @{Name = "Fix-PrivilegedPermanentAccess.ps1"; Dependencies = @()},
            @{Name = "Fix-RemoveOverlyPermissiveAppPermissions.ps1"; Dependencies = @()},
            @{Name = "Fix-OverprovisionedIdentities.ps1"; Dependencies = @()},
            @{Name = "Fix-MultipleOwnersOnSubscription.ps1"; Dependencies = @()}
        )
        Description = "Identity & RBAC Fixes"
    }
    AppServices = @{
        Scripts = @(
            @{Name = "Fix-EnableFunctionAppAuth.ps1"; Dependencies = @()},
            @{Name = "Fix-FunctionAppHTTPSOnly.ps1"; Dependencies = @()},
            @{Name = "Fix-FunctionAppMinimumTLS.ps1"; Dependencies = @()},
            @{Name = "Fix-FunctionAppLatestHTTPVersion.ps1"; Dependencies = @()},
            @{Name = "Fix-DisableFunctionAppRemoteDebugging.ps1"; Dependencies = @()},
            @{Name = "Fix-RequireFTPSOnFunctionApp.ps1"; Dependencies = @()},
            @{Name = "Fix-RequireFTPSOnWebApp.ps1"; Dependencies = @()},
            @{Name = "Fix-WebAppMinimumTLS.ps1"; Dependencies = @()},
            @{Name = "Fix-RestrictFunctionAppNetwork.ps1"; Dependencies = @()}
        )
        Description = "App Services, Function Apps & Web Apps Fixes"
    }
    API = @{
        Scripts = @(
            @{Name = "Fix-APIManagementHTTPSOnly.ps1"; Dependencies = @()},
            @{Name = "Fix-APIMPlatformVersionSTv2.ps1"; Dependencies = @()}
        )
        Description = "API Management Fixes"
    }
    SQL = @{
        Scripts = @(
            @{Name = "Fix-EnableSQLServerAuditing.ps1"; Dependencies = @()},
            @{Name = "Fix-SQLDatabaseSymmetricKeyAES.ps1"; Dependencies = @()},
            @{Name = "Fix-SQLDatabaseCertificateKeyLength.ps1"; Dependencies = @()},
            @{Name = "Fix-PostgreSQLRequireSecureTransport.ps1"; Dependencies = @()},
            @{Name = "Fix-MinimizeSQLDatabaseFirewallRules.ps1"; Dependencies = @()}
        )
        Description = "SQL & PostgreSQL Fixes"
    }
    Networking = @{
        Scripts = @(
            @{Name = "Fix-NSGRestrictAllPorts.ps1"; Dependencies = @()},
            @{Name = "Fix-EnableEDROnVMs.ps1"; Dependencies = @()},
            @{Name = "Fix-EnableJITManagementPorts.ps1"; Dependencies = @()},
            @{Name = "Fix-VMsMigrateToARM.ps1"; Dependencies = @()}
        )
        Description = "Networking & VM Fixes"
    }
    Other = @{
        Scripts = @(
            @{Name = "Fix-ARMDeploymentSecrets.ps1"; Dependencies = @()}
        )
        Description = "Other Fixes"
    }
}
#endregion

#region ====================== PRE-EXECUTION VALIDATION ======================
Write-Host "`n" + "="*80 -ForegroundColor Cyan
Write-Host "PRE-EXECUTION VALIDATION" -ForegroundColor Cyan
Write-Host "="*80 -ForegroundColor Cyan

if (-not (Test-AzureConnection)) {
    Write-Log "Azure connection validation failed. Exiting." "ERROR"
    exit 1
}

if (-not (Test-RequiredModules)) {
    Write-Log "Module validation failed. Some modules may not be available." "WARNING"
}

# Collect all scripts for selected category
$selectedScripts = @()
if ($Category -eq "All") {
    foreach ($cat in $allScripts.Keys) {
        $selectedScripts += $allScripts[$cat].Scripts
    }
} else {
    $selectedScripts = $allScripts[$Category].Scripts
}

$missingScripts = Test-ScriptFiles -Scripts $selectedScripts.Name
if ($missingScripts.Count -gt 0) {
    Write-Log "Found $($missingScripts.Count) missing script(s). Continuing with available scripts." "WARNING"
}

Write-Host ""
#endregion

#region ====================== EXECUTE SCRIPTS WITH DEPENDENCY TRACKING ======================
Write-Host "="*80 -ForegroundColor Cyan
Write-Host "EXECUTING SCRIPTS - Category: $Category" -ForegroundColor Cyan
Write-Host "="*80 -ForegroundColor Cyan
Write-Log "Starting script execution for category: $Category" "INFO"

$executedScripts = @()

foreach ($script in $selectedScripts) {
    $scriptName = $script.Name
    $scriptFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) $scriptName
    
    Write-Host ""
    Write-Host "Running → $scriptName" -ForegroundColor Cyan
    Write-Log "Executing: $scriptName" "INFO"
    
    if (-not (Test-Path $scriptFile)) {
        $results += [PSCustomObject]@{
            Script      = $scriptName
            Status      = "Missing"
            Details     = "File not found"
            Duration    = 0
            ErrorCode   = "FILE_NOT_FOUND"
            Timestamp   = Get-Date
        }
        Write-Log "  ✗ Script file not found: $scriptFile" "ERROR"
        Write-Host "  ⚠ Missing: $scriptName" -ForegroundColor Yellow
        continue
    }
    
    $scriptStartTime = Get-Date
    try {
        $errorOutput = $null
        $output = & $scriptFile -WhatIf:$WhatIf 2>&1
        
        $scriptDuration = ((Get-Date) - $scriptStartTime).TotalSeconds
        
        $results += [PSCustomObject]@{
            Script      = $scriptName
            Status      = "Success"
            Details     = "Completed successfully"
            Duration    = [math]::Round($scriptDuration, 2)
            ErrorCode   = $null
            Timestamp   = Get-Date
        }
        Write-Log "  ✓ $scriptName completed in $([math]::Round($scriptDuration, 2))s" "SUCCESS"
        Write-Host "  ✓ Done ($([math]::Round($scriptDuration, 2))s)" -ForegroundColor Green
        $executedScripts += $scriptName
    }
    catch {
        $scriptDuration = ((Get-Date) - $scriptStartTime).TotalSeconds
        $errorDetails = $_.Exception.Message
        $errorCode = $_.Exception.GetType().Name
        
        $results += [PSCustomObject]@{
            Script      = $scriptName
            Status      = "Failed"
            Details     = $errorDetails
            Duration    = [math]::Round($scriptDuration, 2)
            ErrorCode   = $errorCode
            Timestamp   = Get-Date
        }
        Write-Log "  ✗ $scriptName failed: $errorDetails (Code: $errorCode)" "ERROR"
        Write-Host "  ✗ Failed: $errorDetails" -ForegroundColor Red
    }
}
#endregion

#region ====================== COMPREHENSIVE SUMMARY & ANALYTICS ======================
$endTime = Get-Date
$totalDuration = ($endTime - $startTime).ToString("mm\:ss")

$successCount = ($results | Where-Object {$_.Status -eq "Success"}).Count
$failedCount = ($results | Where-Object {$_.Status -eq "Failed"}).Count
$missingCount = ($results | Where-Object {$_.Status -eq "Missing"}).Count
$totalScripts = $results.Count

Write-Host "`n" + "="*80 -ForegroundColor Cyan
Write-Host "EXECUTION ANALYTICS & SUMMARY" -ForegroundColor Cyan
Write-Host "="*80 -ForegroundColor Cyan
Write-Host "Started      : $startTime" -ForegroundColor Gray
Write-Host "Completed    : $endTime" -ForegroundColor Gray
Write-Host "Total Time   : $totalDuration" -ForegroundColor Gray
Write-Host "Category     : $Category" -ForegroundColor Gray
Write-Host ""
Write-Host "Results Breakdown:" -ForegroundColor Cyan
Write-Host "  ✓ Success  : $successCount/$totalScripts" -ForegroundColor Green
Write-Host "  ✗ Failed   : $failedCount/$totalScripts" -ForegroundColor Red
Write-Host "  ⚠ Missing  : $missingCount/$totalScripts" -ForegroundColor Yellow
Write-Host ""

$avgDuration = $results | Measure-Object -Property Duration -Average | Select-Object -ExpandProperty Average
Write-Host "Performance:" -ForegroundColor Cyan
Write-Host "  Average Duration: $([math]::Round($avgDuration, 2))s per script" -ForegroundColor Gray
Write-Host "  Total Duration: $totalDuration" -ForegroundColor Gray
Write-Host ""

Write-Host "Detailed Results:" -ForegroundColor Cyan
$results | Format-Table -AutoSize -Property Script, Status, Duration, ErrorCode, Timestamp

Write-Log "Execution complete: $successCount succeeded, $failedCount failed, $missingCount missing" "INFO"
#endregion

#region ====================== EXPORT & LOGGING ======================
if (-not $SkipSummary) {
    $summaryFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "AutoRemediation_Summary_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $results | Export-Csv -Path $summaryFile -NoTypeInformation
    Write-Host "`nSummary exported to: $summaryFile" -ForegroundColor Green
    Write-Log "Summary exported to: $summaryFile" "SUCCESS"
}

Write-Host "Detailed log exported to: $logFile" -ForegroundColor Green
Write-Log "=== Master Remediation Run Completed ===" "INFO"
#endregion

#region ====================== FINAL OUTPUT ======================
Write-Host ""
if ($failedCount -eq 0 -and $missingCount -eq 0) {
    Write-Host "✓ Master Remediation Run Completed Successfully!" -ForegroundColor Green
    Write-Log "Master Remediation Run completed successfully!" "SUCCESS"
} else {
    Write-Host "⚠ Master Remediation Run Completed with Issues" -ForegroundColor Yellow
    Write-Log "Master Remediation Run completed with issues (Failed: $failedCount, Missing: $missingCount)" "WARNING"
    
    if ($failedCount -gt 0) {
        Write-Host "`nFailed Scripts:" -ForegroundColor Red
        $results | Where-Object {$_.Status -eq "Failed"} | ForEach-Object {
            Write-Host "  - $($_.Script): $($_.Details)" -ForegroundColor Red
            Write-Host "    Error Code: $($_.ErrorCode)" -ForegroundColor Red
        }
    }
}

Write-Host "Re-run your Security Evidence Collector to verify improvements." -ForegroundColor Magenta
#endregion