# Azure Security Auto-Remediation - Automation Guide

## Overview

This guide provides a comprehensive automation architecture to keep your Azure environment in a continuously compliant ("green") state using scheduled remediation and continuous monitoring.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AUTOMATION ARCHITECTURE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐    ┌──────────────────┐    ┌────────────────────────────┐ │
│  │  Schedule   │───▶│ Azure Automation │───▶│  Azure Security Toolkit    │ │
│  │  Triggers   │     │   Runbooks       │    │  Run-AllAutoFix.ps1        │ │
│  └──────────────┘    └──────────────────┘    │  Run-AllPolicyCompliance   │ │
│                                               └────────────────────────────┘ │
│  ┌──────────────┐    ┌──────────────────┐              │                   │
│  │ Monitoring   │◀───│ Alert Rules      │◀─────────────┘                   │
│  │ (Defender)   │    │ & Notifications  │                                  │
│  └──────────────┘    └──────────────────┘                                  │
│                                                                             │
│  ┌──────────────┐    ┌──────────────────┐    ┌────────────────────────────┐ │
│  │ Service      │───▶│ Key Vault        │───▶│ Automation Account         │ │
│  │ Principal    │    │ (Credential)     │    │ (Secure Execution)         │ │
│  └──────────────┘    └──────────────────┘    └────────────────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Recommended Approach: Azure Automation

### Why Azure Automation?

| Feature | Azure Automation | GitHub Actions | Local Scheduler |
|---------|------------------|----------------|-----------------|
| Native Azure Integration | ✓✓✓ | Limited | None |
| Managed Identity | ✓✓✓ | Limited | None |
| Schedule Flexibility | ✓✓✓ | ✓ | ✓ |
| Credential Management | ✓✓✓ | Limited | None |
| Hybrid Worker Support | ✓✓ | ✗ | ✓ |
| Cost | Free tier available | Minutes limited | None |

---

## Implementation Guide

### Phase 1: Service Principal Setup

#### Step 1.1: Create Service Principal

```powershell
# Connect to Azure AD
Connect-AzureAD

# Create a new Service Principal for automation
$sp = New-AzureADServicePrincipal `
    -DisplayName "Azure-Security-Automation-SP" `
    -AppId $(New-Guid).ToString() `
    -PasswordCredentials $(New-AzureADPasswordCredential -StartDate (Get-Date) -EndDate (Get-Date).AddYears(2))

# Note the AppId and Password for later use
$AppId = $sp.AppId
$Password = <the password you set>
$TenantId = (Get-AzureADTenantDetail).ObjectId

Write-Host "AppId: $AppId"
Write-Host "TenantId: $TenantId"
```

#### Step 1.2: Grant Required Permissions

```powershell
# Get the Service Principal Object ID
$spObjectId = (Get-AzureADServicePrincipal -Filter "AppId eq '$AppId'").ObjectId

# Role assignments at Management Group level (recommended)
$managementGroupId = "your-mg-id"

# Assign roles at Management Group scope
New-AzRoleAssignment `
    -ObjectId $spObjectId `
    -RoleDefinitionName "Security Admin" `
    -Scope "/providers/Microsoft.Management/managementGroups/$managementGroupId"

New-AzRoleAssignment `
    -ObjectId $spObjectId `
    -RoleDefinitionName "Contributor" `
    -Scope "/providers/Microsoft.Management/managementGroups/$managementGroupId"

# Or at Subscription level
$subscriptionId = "your-subscription-id"
New-AzRoleAssignment `
    -ObjectId $spObjectId `
    -RoleDefinitionName "Security Admin" `
    -Scope "/subscriptions/$subscriptionId"

New-AzRoleAssignment `
    -ObjectId $spObjectId `
    -RoleDefinitionName "Contributor" `
    -Scope "/subscriptions/$subscriptionId"
```

**Required Roles:**

| Role | Scope | Purpose |
|------|-------|---------|
| Security Admin | MG/Subscription | Assign policies, view compliance |
| Contributor | MG/Subscription | Modify resource configurations |
| Key Vault Secrets Officer | Key Vault | Read credentials from Key Vault |
| Monitoring Reader | MG/Subscription | Read security alerts |

---

### Phase 2: Azure Automation Setup

#### Step 2.1: Create Automation Account

```powershell
# Create Resource Group (if needed)
New-AzResourceGroup -Name "automation-rg" -Location "eastus"

# Create Automation Account
New-AzAutomationAccount `
    -Name "azure-security-automation" `
    -ResourceGroupName "automation-rg" `
    -Location "eastus" `
    -Sku "Basic"
```

#### Step 2.2: Store Credentials in Key Vault

```powershell
# Create Key Vault
New-AzKeyVault `
    -Name "azure-security-kv" `
    -ResourceGroupName "automation-rg" `
    -Location "eastus" `
    -EnableRbacAuthorization `
    -EnableSoftDelete `
    -EnablePurgeProtection

# Grant Automation SP access to Key Vault
$spObjectId = (Get-AzureADServicePrincipal -Filter "DisplayName eq 'Azure-Security-Automation-SP'").ObjectId

Set-AzKeyVaultAccessPolicy `
    -VaultName "azure-security-kv" `
    -ObjectId $spObjectId `
    -PermissionsToSecrets "Get", "List"

# Store credentials as secrets
$securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
Set-AzKeyVaultSecret -VaultName "azure-security-kv" -Name "automation-appid" -SecretValue $(ConvertTo-SecureString $AppId -AsPlainText -Force)
Set-AzKeyVaultSecret -VaultName "azure-security-kv" -Name "automation-password" -SecretValue $securePassword
Set-AzKeyVaultSecret -VaultName "azure-security-kv" -Name "automation-tenant" -SecretValue $(ConvertTo-SecureString $TenantId -AsPlainText -Force)
```

#### Step 2.3: Create Azure Automation Runbook

Create a master runbook that orchestrates the full automation:

```powershell
# Import the script as a runbook
$automationAccount = Get-AzAutomationAccount -ResourceGroupName "automation-rg"
$content = Get-Content ".\Run-AllAutoFix.ps1" -Raw

Import-AzAutomationRunbook `
    -Name "Azure-Security-AutoRemediation" `
    -ResourceGroupName "automation-rg" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -Type PowerShell `
    -Description "Automated security remediation" `
    -LogProgress $true `
    -LogVerbose $true
```

#### Step 2.4: Create Automation Variables

```powershell
$automationAccount = Get-AzAutomationAccount -ResourceGroupName "automation-rg"

# Create automation variables
New-AzAutomationVariable `
    -Name "KeyVaultName" `
    -ResourceGroupName "automation-rg" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -Type String `
    -Value "azure-security-kv"

New-AzAutomationVariable `
    -Name "ManagementGroupId" `
    -ResourceGroupName "automation-rg" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -Type String `
    -Value "your-mg-id"

New-AzAutomationVariable `
    -Name "LogAnalyticsWorkspaceId" `
    -ResourceGroupName "automation-rg" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -Type String `
    -Value "workspace-id"
```

---

### Phase 3: The Master Automation Runbook

Create a comprehensive runbook that handles:

1. **Authentication** - Secure credential retrieval
2. **Execution** - Run remediation scripts
3. **Reporting** - Generate compliance reports
4. **Alerting** - Notify on failures
5. **Idempotency** - Safe to re-run

```powershell
<#
.SYNOPSIS
    Azure Security Auto-Remediation Master Runbook
    Scheduled execution for continuous compliance

    Version: 1.0
    Schedule: Every 6 hours (recommended)
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("High", "Critical", "All")]
    [string]$Severity = "High",

    [Parameter(Mandatory=$false)]
    [string]$WebhookData
)

$ErrorActionPreference = "Continue"
$runbookStartTime = Get-Date

# =====================================================
# CONFIGURATION
# =====================================================
$config = @{
    KeyVaultName           = Get-AutomationVariable -Name "KeyVaultName"
    ManagementGroupId      = Get-AutomationVariable -Name "ManagementGroupId"
    LogAnalyticsWorkspace  = Get-AutomationVariable -Name "LogAnalyticsWorkspaceId"
    ScriptsPath            = "Auto Remediation Azure Security Recommendations"
    OutputPath             = ".\Outputs"
}

Write-Output "=== Azure Security Auto-Remediation Runbook ==="
Write-Output "Start Time: $runbookStartTime"
Write-Output "Severity Filter: $Severity"

# =====================================================
# STEP 1: AUTHENTICATION
# =====================================================
Write-Output "`n[1/5] Authenticating to Azure..."

try {
    $appId = Get-AzKeyVaultSecret -VaultName $config.KeyVaultName -Name "automation-appid" -ErrorAction Stop
    $password = Get-AzKeyVaultSecret -VaultName $config.KeyVaultName -Name "automation-password" -ErrorAction Stop
    $tenantId = Get-AzKeyVaultSecret -VaultName $config.KeyVaultName -Name "automation-tenant" -ErrorAction Stop

    $secPassword = ConvertTo-SecureString $password.SecretValue -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($appId.SecretValue, $secPassword)

    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $tenantId.SecretValue -ErrorAction Stop
    Write-Output "  ✓ Authentication successful"
}
catch {
    Write-Error "  ✗ Authentication failed: $($_.Exception.Message)"
    throw
}

# =====================================================
# STEP 2: CHECK CURRENT COMPLIANCE
# =====================================================
Write-Output "`n[2/5] Checking current compliance state..."

$complianceReport = @()

try {
    $nonCompliant = Get-AzPolicyState -Filter "ComplianceState eq 'NonCompliant'" -All |
                    Where-Object { $_.PolicyDefinitionName -ne $null }

    $criticalCount = ($nonCompliant | Where-Object { $_.PolicyDefinitionName -like "*Critical*" }).Count
    $highCount = ($nonCompliant | Where-Object { $_.PolicyDefinitionName -like "*High*" }).Count
    $totalCount = $nonCompliant.Count

    $complianceReport = @{
        TotalNonCompliant = $totalCount
        Critical = $criticalCount
        High = $highCount
        Timestamp = Get-Date
    }

    Write-Output "  Current State: $totalCount non-compliant resources"
    Write-Output "  - Critical: $criticalCount"
    Write-Output "  - High: $highCount"
}
catch {
    Write-Warning "  ⚠ Could not fetch compliance state: $($_.Exception.Message)"
}

# =====================================================
# STEP 3: EXECUTE AUTO-REMEDIATION
# =====================================================
Write-Output "`n[3/5] Executing auto-remediation scripts..."

$remediationResults = @{
    Success = 0
    Failed = 0
    Skipped = 0
}

# Define scripts to run based on severity
$scriptsToRun = @(
    # Critical scripts - always run
    "Fix-EnableDefenderPlans.ps1",
    "Fix-EnableKeyVaultPurgeProtection.ps1",
    "Fix-RemoveGuestOwnerAccounts.ps1",
    "Fix-RemoveDisabledOwnerAccounts.ps1"
)

# Add high-severity scripts if Severity is "All"
if ($Severity -eq "All") {
    $scriptsToRun += @(
        "Fix-StorageAccountTLS.ps1",
        "Fix-StorageSecureTransfer.ps1",
        "Fix-EnableKeyVaultSoftDelete.ps1",
        "Fix-EnableKeyVaultRBAC.ps1",
        "Fix-FunctionAppHTTPSOnly.ps1",
        "Fix-FunctionAppMinimumTLS.ps1",
        "Fix-EnableFunctionAppAuth.ps1",
        "Fix-NSGRestrictAllPorts.ps1",
        "Fix-EnableSQLServerAuditing.ps1"
    )
}

# Execute each script
foreach ($script in $scriptsToRun) {
    $scriptPath = Join-Path $config.ScriptsPath $script

    if (Test-Path $scriptPath) {
        Write-Output "  Running: $script"
        try {
            & $scriptPath -WhatIf:$false
            $remediationResults.Success++
        }
        catch {
            Write-Warning "  ⚠ Script failed: $script - $($_.Exception.Message)"
            $remediationResults.Failed++
        }
    }
    else {
        Write-Warning "  ⚠ Script not found: $script"
        $remediationResults.Skipped++
    }
}

Write-Output "`n  Remediation Summary:"
Write-Output "  - Success: $($remediationResults.Success)"
Write-Output "  - Failed: $($remediationResults.Failed)"
Write-Output "  - Skipped: $($remediationResults.Skipped)"

# =====================================================
# STEP 4: GENERATE COMPLIANCE REPORT
# =====================================================
Write-Output "`n[4/5] Generating compliance report..."

try {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $reportPath = Join-Path $config.OutputPath "ComplianceReport_$timestamp.csv"

    # Export compliance summary
    $summary = [PSCustomObject]@{
        RunbookStartTime = $runbookStartTime
        RunbookEndTime = Get-Date
        Severity = $Severity
        TotalNonCompliant = $complianceReport.TotalNonCompliant
        SuccessCount = $remediationResults.Success
        FailedCount = $remediationResults.Failed
        Status = if ($remediationResults.Failed -eq 0) { "Green" } else { "Yellow" }
    }

    $summary | Export-Csv -Path $reportPath -NoTypeInformation -Append
    Write-Output "  ✓ Report saved: $reportPath"
}
catch {
    Write-Warning "  ⚠ Could not generate report: $($_.Exception.Message)"
}

# =====================================================
# STEP 5: SEND NOTIFICATIONS
# =====================================================
Write-Output "`n[5/5] Checking for alerts..."

if ($remediationResults.Failed -gt 0) {
    Write-Output "  ⚠ Sending failure notification..."

    # Send to Log Analytics (if configured)
    # Or send email via webhook

    # Example: Write to Log Analytics
    $logEntry = @{
        Category = "SecurityRemediation"
        RunbookName = "Azure-Security-AutoRemediation"
        Severity = "Warning"
        FailedScripts = $remediationResults.Failed
        Timestamp = Get-Date
    }

    # Uncomment to send to Log Analytics
    # Send-AzOMSWorkspacesAlertData -WorkspaceId $config.LogAnalyticsWorkspace -LogEntry $logEntry
}

# =====================================================
# FINAL STATUS
# =====================================================
$runbookEndTime = Get-Date
$duration = ($runbookEndTime - $runbookStartTime).TotalMinutes

Write-Output "`n=== Runbook Completed ==="
Write-Output "End Time: $runbookEndTime"
Write-Output "Duration: $([math]::Round($duration, 2)) minutes"

if ($remediationResults.Failed -eq 0) {
    Write-Output "Status: GREEN ✓"
}
else {
    Write-Output "Status: YELLOW ⚠ ($($remediationResults.Failed) failures)"
}

# Return status for Azure Monitor
return @{
    Status = if ($remediationResults.Failed -eq 0) { "Success" } else { "PartialSuccess" }
    Duration = $duration
    SuccessCount = $remediationResults.Success
    FailedCount = $remediationResults.Failed
}
```

---

### Phase 4: Schedule Configuration

#### Create Schedules

```powershell
$automationAccount = Get-AzAutomationAccount -ResourceGroupName "automation-rg"

# Schedule: Every 6 hours (recommended for green state)
New-AzAutomationSchedule `
    -Name "Every6Hours" `
    -ResourceGroupName "automation-rg" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -HourInterval 6 `
    -Frequency Hour `
    -StartTime (Get-Date) `
    -Description "Run security remediation every 6 hours"

# Schedule: Daily at midnight
New-AzAutomationSchedule `
    -Name "DailyMidnight" `
    -ResourceGroupName "automation-rg" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -DayInterval 1 `
    -Frequency Day `
    -StartTime (Get-Date "00:00") `
    -Description "Daily compliance check at midnight"

# Schedule: Weekly on Sunday at 3 AM
New-AzAutomationSchedule `
    -Name "WeeklySunday3AM" `
    -ResourceGroupName "automation-rg" `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -DaysOfWeek Sunday `
    -Hour 3 `
    -Frequency Week `
    -StartTime (Get-Date) `
    -Description "Weekly full scan"

# Link schedules to runbook
$runbook = Get-AzAutomationRunbook -ResourceGroupName "automation-rg" -AutomationAccountName $automationAccount.AutomationAccountName -Name "Azure-Security-AutoRemediation"

Register-AzAutomationScheduledRunbook `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -ScheduleName "Every6Hours" `
    -ResourceGroupName "automation-rg" `
    -RunbookName $runbook.Name `
    -Parameters @{ Severity = "High" }

Register-AzAutomationScheduledRunbook `
    -AutomationAccountName $automationAccount.AutomationAccountName `
    -ScheduleName "WeeklySunday3AM" `
    -ResourceGroupName "automation-rg" `
    -RunbookName $runbook.Name `
    -Parameters @{ Severity = "All" }
```

---

### Phase 5: Monitoring and Alerting

#### Create Alert Rules

```powershell
# Alert when remediation fails
$alertRule = New-AzAlertRule `
    -Name "SecurityRemediation-Failure" `
    -ResourceGroupName "automation-rg" `
    -Condition "AzureAutomationJob.Outcome = 'Failed'" `
    -Description "Security remediation runbook failed"

# Alert when compliance drops below threshold
$complianceThreshold = 85  # Alert if compliance drops below 85%

# Send alerts to email/webhook
New-AzAlertEmail `
    -Recipients "security-team@yourcompany.com" `
    -Location "eastus"
```

---

## Recommended Schedule Strategy

| Schedule | Frequency | When | Severity | Purpose |
|----------|-----------|------|----------|---------|
| **Continuous** | Every 6 hours | 00:00, 06:00, 12:00, 18:00 | High | Maintain green state |
| **Daily** | Every 24 hours | 02:00 | Critical | Catch critical issues |
| **Weekly** | Every Sunday | 03:00 | All | Full comprehensive scan |

### Auto-Remediation Tiers

| Tier | Scripts | When to Run | Rationale |
|------|---------|-------------|-----------|
| **Critical** | Defender, Key Vault, Guest Accounts | Every 6 hours | Prevent major security gaps |
| **High** | Storage, Function Apps, SQL | Every 12 hours | Maintain best practices |
| **Medium** | Network, Monitoring | Daily | Optimize cost/effort |
| **All** | Everything | Weekly | Comprehensive review |

---

## Alternative Approaches

### Option 1: Azure Logic Apps

Use Azure Logic Apps for event-driven remediation:

```json
{
  "trigger": {
    "recurrence": {
      "frequency": "Hour",
      "interval": 6
    }
  },
  "actions": [
    {
      "type": "Http",
      "method": "POST",
      "uri": "https://management.azure.com/.../runbooks/.../start"
    }
  ]
}
```

### Option 2: GitHub Actions

```yaml
name: Azure Security Remediation
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours

jobs:
  remediate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      - name: Run Remediation
        run: |
          pwsh -File ./Run-AllAutoFix.ps1
```

### Option 3: Azure Functions

For more complex scenarios with queue-based processing.

---

## Keeping Environment in Green State

### The Green State Framework

```
┌─────────────────────────────────────────────────────────────┐
│                    GREEN STATE MODEL                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   DETECT    │───▶│   REMEDIATE  │───▶│   VERIFY    │     │
│  │  (Monitor)  │    │  (Automate)  │    │  (Report)   │     │
│  └─────────────┘    └─────────────┘    └──────┬──────┘     │
│                                                │            │
│                     ◀──────────────────────────┘            │
│                     (Continuous Loop)                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Detection Layer

| Source | What it Detects | Frequency |
|--------|-----------------|-----------|
| Microsoft Defender | Vulnerabilities, Threats | Real-time |
| Azure Policy | Compliance violations | Hourly |
| Azure Advisor | Optimization opportunities | Daily |
| Security Center | Security recommendations | Real-time |

### Remediation Layer

| Tier | Response Time | Scripts | Schedule |
|------|---------------|---------|----------|
| Critical | < 15 minutes | Defender, Key Vault | Every 15 min |
| High | < 1 hour | Storage, Identity, Function Apps | Every hour |
| Medium | < 6 hours | SQL, Networking | Every 6 hours |
| Low | < 24 hours | Everything | Daily |

### Verification Layer

| Check | Method | Alert Threshold |
|-------|--------|-----------------|
| Compliance Score | Get-AzPolicyState | < 90% |
| Failed Remediation | Runbook output | > 0 failures |
| New Vulnerabilities | Defender alerts | Any Critical |
| Drift Detection | Azure Resource Graph | Any change |

---

## Quick Start: Deploy Complete Automation

### One-Command Deployment

```powershell
# Deploy complete automation stack
# 1. Create resource group
# 2. Create Automation account
# 3. Import runbook
# 4. Configure schedules
# 5. Set up monitoring

$params = @{
    ResourceGroupName = "automation-rg"
    Location = "eastus"
    KeyVaultName = "azure-security-kv"
    ManagementGroupId = "your-mg-id"
    ScheduleIntervalHours = 6
}

# Run the deployment script
.\Deploy-Automation.ps1 @params
```

---

## Troubleshooting

### Common Issues

#### Issue: Runbook fails with "Insufficient privileges"
**Solution:** Verify Service Principal has required roles at MG scope

#### Issue: Key Vault access denied
**Solution:** Enable RBAC on Key Vault and grant "Key Vault Secrets Officer" role

#### Issue: Scripts run but don't remediate
**Solution:** Check subscription-level permissions; Contributor role required

### Monitoring Job Status

```powershell
# Check runbook job status
Get-AzAutomationJob `
    -ResourceGroupName "automation-rg" `
    -AutomationAccountName "azure-security-automation" `
    -RunbookName "Azure-Security-AutoRemediation" |
    Sort-Object StartTime -Descending |
    Select-Object -First 10

# View job output
Get-AzAutomationJobOutput `
    -ResourceGroupName "automation-rg" `
    -AutomationAccountName "azure-security-automation" `
    -JobId "job-id"
```

---

## Security Considerations

1. **Use Managed Identity** where possible (avoids credential management)
2. **Store credentials in Key Vault** (never hardcode in runbooks)
3. **Use least privilege** (only assign required roles)
4. **Enable audit logging** on all automation activities
5. **Review runbook execution logs** regularly
6. **Implement approval gates** for production changes

---

## Summary: Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GREEN STATE AUTOMATION                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  SCHEDULE TRIGGERS                                                          │
│  ├─ Every 6 hours: High severity fixes                                       │
│  ├─ Daily: Critical fixes                                                    │
│  └─ Weekly: Full comprehensive scan                                         │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                     AZURE AUTOMATION ACCOUNT                          │  │
│  │  ┌─────────────────┐  ┌──────────────────┐  ┌────────────────────┐   │  │
│  │  │ Master Runbook  │  │  Credential      │  │  Variables &       │   │  │
│  │  │ AutoRemediation │  │  (Key Vault)     │  │  Schedules         │   │  │
│  │  └────────┬────────┘  └──────────────────┘  └────────────────────┘   │  │
│  └──────────┼────────────────────────────────────────────────────────────┘  │
│             │                                                                │
│  ┌──────────▼────────────────────────────────────────────────────────────┐  │
│  │                         EXECUTION LAYER                               │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐               │  │
│  │  │ Run-All      │  │ Policy       │  │ Defender     │               │  │
│  │  │ AutoFix.ps1  │  │ Compliance   │  │ Enable       │               │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘               │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌───────────────────────────▼──────────────────────────────────────────┐  │
│  │                    MONITORING & ALERTING                              │  │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────────────┐   │  │
│  │  │ Log Analytics  │  │ Azure Monitor  │  │ Email/Webhook Alerts   │   │  │
│  │  │ Workspace      │  │ Alerts         │  │ on Failures            │   │  │
│  │  └────────────────┘  └────────────────┘  └────────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

*Version: 1.0*
*Document Created: 2026-05-08*