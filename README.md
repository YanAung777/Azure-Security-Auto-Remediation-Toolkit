# Azure Security Auto-Remediation Toolkit

## Overview

This toolkit provides automated PowerShell scripts to remediate Azure security recommendations and manage Azure Policy compliance. It consists of two main components:

1. **Auto Remediation Azure Security Recommendations** - 45 individual fix scripts + master runner
2. **Azure Policy Compliance & Remediation** - Policy compliance reporting and remediation tools

---

## Prerequisites

### Required Modules

Install the following PowerShell modules before running:

```powershell
# Azure PowerShell Module (all scripts require this)
Install-Module Az -Scope CurrentUser -Force

# Microsoft Graph Module (for identity scripts)
Install-Module Microsoft.Graph.Users -Scope CurrentUser -Force

# Excel Export Module (optional, for reports)
Install-Module ImportExcel -Scope CurrentUser -Force
```

### Required Permissions

| Permission Level | Scope | Required For |
|-----------------|-------|--------------|
| **Owner** or **User Access Administrator** | Subscription or Management Group | Identity & RBAC scripts |
| **Contributor** | Resource Group | Most remediation scripts |
| **Security Admin** or **Owner** | Management Group | Policy compliance scripts |

---

## Quick Start

### 1. Connect to Azure

```powershell
# Connect with your Azure account
Connect-AzAccount

# Or connect to a specific tenant
Connect-AzAccount -TenantId "your-tenant-id"
```

### 2. Run Auto-Remediation

```powershell
# Navigate to the Auto Remediation folder
cd "Auto Remediation Azure Security Recommendations"

# Dry run first (recommended)
.\Run-AllAutoFix.ps1 -WhatIf

# Actual run (all categories)
.\Run-AllAutoFix.ps1

# Run specific category
.\Run-AllAutoFix.ps1 -Category KeyVault

# Run specific category with WhatIf preview
.\Run-AllAutoFix.ps1 -Category Storage -WhatIf

# Skip CSV summary export
.\Run-AllAutoFix.ps1 -SkipSummary
```

#### Run-AllAutoFix.ps1 Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-WhatIf` | Switch | False | Preview changes without executing them |
| `-SkipSummary` | Switch | False | Skip CSV export of execution results |
| `-Category` | String | All | Run specific security category (All, Storage, KeyVault, Defender, Identity, AppServices, API, SQL, Networking, Other) |

**Available Categories:**
- `All` - Runs all remediation scripts across all categories
- `Storage` - 5 scripts for Storage Account security
- `KeyVault` - 4 scripts for Key Vault security
- `Defender` - 1 script to enable Microsoft Defender plans
- `Identity` - 10 scripts for Identity & RBAC management
- `AppServices` - 9 scripts for App Services, Function Apps, and Web Apps
- `API` - 2 scripts for API Management
- `SQL` - 5 scripts for SQL and PostgreSQL databases
- `Networking` - 4 scripts for Network Security and VMs
- `Other` - 1 script for other security fixes

**Output Files:**
- `AutoRemediation_Log_[timestamp].txt` - Detailed execution log with all operations and errors
- `AutoRemediation_Summary_[timestamp].csv` - Summary results (unless `-SkipSummary` is used)

**Example Outputs:**
```
Category: KeyVault
Found 2 subscription(s)

Processing subscription: Production (xxx-xxx-xxx)
  Enabling plan: Fix-EnableKeyVaultSoftDelete.ps1
    ✓ Enabled (1.25s)
  Enabling plan: Fix-EnableKeyVaultRBAC.ps1
    ✓ Enabled (0.87s)

EXECUTION ANALYTICS & SUMMARY
Results Breakdown:
  ✓ Success  : 2/2
  ✗ Failed   : 0/2
  ⚠ Missing  : 0/2

Detailed Results:
Script                               Status Duration ErrorCode Timestamp
------                               ------ -------- --------- ---------
Fix-EnableKeyVaultSoftDelete.ps1     Success    1.25 <null>    5/9/2026...
Fix-EnableKeyVaultRBAC.ps1           Success    0.87 <null>    5/9/2026...
```

### 3. Run Policy Compliance

```powershell
# Navigate to the Policy Compliance folder
cd "Azure Policy Compliance & Remediation"

# Full compliance run
.\Run-AllPolicyComplianceTools.ps1

# Dry run with specific severity
.\Run-AllPolicyComplianceTools.ps1 -WhatIf -Severity Critical
```

---

## Script Catalog

### Auto Remediation Scripts

#### Category: Storage (5 Scripts)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Fix-StorageAccountTLS.ps1` | Enforce minimum TLS 1.2 on Storage Accounts | `-MinimumTlsVersion` (default: TLS1_2) |
| `Fix-StorageSecureTransfer.ps1` | Require secure transfer (HTTPS) | None |
| `Fix-StoragePublicBlobAccess.ps1` | Disable public blob access | None |
| `Fix-StorageAccountKeysExpiration.ps1` | Enable automatic key rotation | None |
| `Fix-StorageAccountDisableSharedKey.ps1` | Disable shared key authentication | None |

**Usage:**
```powershell
.\Fix-StorageAccountTLS.ps1                    # Default: TLS1_2
.\Fix-StorageAccountTLS.ps1 -MinimumTlsVersion "TLS1_2"
.\Fix-StorageAccountTLS.ps1 -WhatIf             # Dry run
```

---

#### Category: Key Vault (4 Scripts)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Fix-EnableKeyVaultSoftDelete.ps1` | Enable soft delete | `-SoftDeleteRetentionDays` (default: 90) |
| `Fix-EnableKeyVaultPurgeProtection.ps1` | Enable purge protection | `-SoftDeleteRetentionDays` (default: 90) |
| `Fix-EnableKeyVaultRBAC.ps1` | Switch to RBAC permission model | None |
| `Fix-KeyVaultSecretExpiration.ps1` | Monitor secret expiration | None |

**Usage:**
```powershell
.\Fix-EnableKeyVaultSoftDelete.ps1                         # Default 90 days
.\Fix-EnableKeyVaultSoftDelete.ps1 -SoftDeleteRetentionDays 60
.\Fix-EnableKeyVaultSoftDelete.ps1 -WhatIf
```

---

#### Category: Microsoft Defender (1 Script)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Fix-EnableDefenderPlans.ps1` | Enable all Microsoft Defender plans | None |

**Plans enabled:**
- VirtualMachines (Defender for Servers)
- StorageAccounts (Defender for Storage)
- AppServices (Defender for App Service)
- SqlServers (Defender for SQL)
- ContainerRegistry (Defender for Containers)
- KeyVaults (Defender for Key Vault)
- Arm (Defender for Resource Manager)
- CSPM (Defender CSPM)
- Apis (Defender for APIs)

**Usage:**
```powershell
.\Fix-EnableDefenderPlans.ps1
.\Fix-EnableDefenderPlans.ps1 -WhatIf
```

---

#### Category: Identity & RBAC (7 Scripts)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Fix-RemoveDisabledOwnerAccounts.ps1` | Remove Owner role from disabled accounts | None |
| `Fix-RemoveDisabledReadWriteAccounts.ps1` | Remove Contributor/Reader from disabled accounts | None |
| `Fix-RemoveGuestOwnerAccounts.ps1` | Remove Owner role from guest accounts | None |
| `Fix-RemoveGuestWriteAccounts.ps1` | Remove write permissions from guest accounts | None |
| `Fix-RemoveGuestReadAccounts.ps1` | Remove Reader role from guest accounts | None |
| `Fix-RemoveInactiveIdentitiesPermissions.ps1` | Remove permissions from inactive users | `-InactiveDays` (default: 90), `-RolesToCheck` |
| `Fix-PrivilegedPermanentAccess.ps1` | Remove permanent privileged role assignments | None |
| `Fix-RemoveOverlyPermissiveAppPermissions.ps1` | Remove excessive app permissions | None |
| `Fix-OverprovisionedIdentities.ps1` | Identify over-provisioned identities | None |
| `Fix-MultipleOwnersOnSubscription.ps1` | Ensure single owner per subscription | None |

**Usage:**
```powershell
.\Fix-RemoveInactiveIdentitiesPermissions.ps1                # Default 90 days
.\Fix-RemoveInactiveIdentitiesPermissions.ps1 -InactiveDays 180
.\Fix-RemoveInactiveIdentitiesPermissions.ps1 -WhatIf

.\Fix-PrivilegedPermanentAccess.ps1
.\Fix-PrivilegedPermanentAccess.ps1 -WhatIf
```

---

#### Category: App Services / Function Apps (8 Scripts)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Fix-EnableFunctionAppAuth.ps1` | Enable App Service Authentication | None |
| `Fix-FunctionAppHTTPSOnly.ps1` | Enforce HTTPS-only access | None |
| `Fix-FunctionAppMinimumTLS.ps1` | Set minimum TLS version | `-MinimumTlsVersion` (default: TLS1_2) |
| `Fix-FunctionAppLatestHTTPVersion.ps1` | Use latest HTTP version | None |
| `Fix-DisableFunctionAppRemoteDebugging.ps1` | Disable remote debugging | None |
| `Fix-RequireFTPSOnFunctionApp.ps1` | Enforce FTPS only | None |
| `Fix-RequireFTPSOnWebApp.ps1` | Enforce FTPS only on Web Apps | None |
| `Fix-WebAppMinimumTLS.ps1` | Set minimum TLS version | `-MinimumTlsVersion` (default: TLS1_2) |
| `Fix-RestrictFunctionAppNetwork.ps1` | Restrict network access | `-AllowedIPRanges` (required) |

**Usage:**
```powershell
.\Fix-FunctionAppHTTPSOnly.ps1
.\Fix-FunctionAppMinimumTLS.ps1 -MinimumTlsVersion "TLS1_2"
.\Fix-RestrictFunctionAppNetwork.ps1 -AllowedIPRanges @("203.0.113.0/24", "198.51.100.0/24")
.\Fix-RestrictFunctionAppNetwork.ps1 -WhatIf
```

⚠️ **Important:** Edit `Fix-RestrictFunctionAppNetwork.ps1` and replace the placeholder IP ranges with your actual corporate IP addresses.

---

#### Category: API Management (2 Scripts)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Fix-APIManagementHTTPSOnly.ps1` | Enforce HTTPS-only on APIs | None |
| `Fix-APIMPlatformVersionSTv2.ps1` | Migrate to STv2 platform | None |

**Usage:**
```powershell
.\Fix-APIManagementHTTPSOnly.ps1
.\Fix-APIManagementHTTPSOnly.ps1 -WhatIf
```

---

#### Category: SQL & PostgreSQL (5 Scripts)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Fix-EnableSQLServerAuditing.ps1` | Enable SQL Server auditing | `-StorageAccountResourceId` |
| `Fix-SQLDatabaseSymmetricKeyAES.ps1` | Recreate keys with AES-256 | `-SqlAdminUser`, `-SqlAdminPassword` |
| `Fix-SQLDatabaseCertificateKeyLength.ps1` | Enforce minimum key length | None |
| `Fix-PostgreSQLRequireSecureTransport.ps1` | Require SSL for PostgreSQL | None |
| `Fix-MinimizeSQLDatabaseFirewallRules.ps1` | Restrict SQL firewall rules | None |

**Usage:**
```powershell
.\Fix-EnableSQLServerAuditing.ps1
.\Fix-EnableSQLServerAuditing.ps1 -StorageAccountResourceId "/subscriptions/xxx/..."

.\Fix-SQLDatabaseSymmetricKeyAES.ps1
.\Fix-SQLDatabaseSymmetricKeyAES.ps1 -SqlAdminUser "sqladmin" -SqlAdminPassword "P@ssw0rd"
.\Fix-SQLDatabaseSymmetricKeyAES.ps1 -WhatIf
```

---

#### Category: Networking & VMs (4 Scripts)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Fix-NSGRestrictAllPorts.ps1` | Add DenyAll rule to NSGs | None |
| `Fix-EnableEDROnVMs.ps1` | Install Microsoft Defender for Endpoint | None |
| `Fix-EnableJITManagementPorts.ps1` | Enable JIT access on VMs | None |
| `Fix-VMsMigrateToARM.ps1` | Report classic VM migration needs | None |

**Usage:**
```powershell
.\Fix-NSGRestrictAllPorts.ps1
.\Fix-NSGRestrictAllPorts.ps1 -WhatIf

.\Fix-EnableEDROnVMs.ps1
.\Fix-VMsMigrateToARM.ps1
```

---

#### Category: Others (1 Script)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Fix-ARMDeploymentSecrets.ps1` | Remove secrets from ARM templates | None |

---

### Policy Compliance Scripts

#### Category: Reporting (5 Scripts)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Export-ManagementGroupPolicyCompliance.ps1` | Export MG-level compliance reports | `-OutputPath`, `-ExportToExcel` |
| `Export-NonCompliantResourcesWithRemediation.ps1` | Export non-compliant resources with fix links | `-OutputPath`, `-ExportToExcel` |
| `Export-PolicyComplianceCSV.ps1` | Export compliance to CSV | `-OutputPath` |
| `Get-PolicyComplianceSummary.ps1` | Get compliance summary | None |
| `Export-ManagementGroupPolicyCompliance.ps1` | Generate Excel reports | `-ExportToExcel` |

**Usage:**
```powershell
.\Export-ManagementGroupPolicyCompliance.ps1
.\Export-ManagementGroupPolicyCompliance.ps1 -ExportToExcel
.\Export-ManagementGroupPolicyCompliance.ps1 -OutputPath ".\Reports"

.\Export-NonCompliantResourcesWithRemediation.ps1
.\Export-NonCompliantResourcesWithRemediation.ps1 -ExportToExcel
```

---

#### Category: Remediation (5 Scripts)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Remediate-NonCompliantResources.ps1` | Generic remediation | `-WhatIf` |
| `Remediate-NonCompliantResources-BySeverity.ps1` | Severity-based remediation | `-Severity`, `-WhatIf`, `-ExportReportOnly` |
| `Remediate-NonCompliantResources-ByMG.ps1` | Remediation by Management Group | `-ManagementGroupId`, `-WhatIf` |
| `Remediate-NonCompliantResources-MultipleMGs.ps1` | Multi-MG remediation | `-ManagementGroupIds`, `-Severity`, `-WhatIf` |
| `Remediate-NonCompliantPolicies.ps1` | Assign missing policies | `-WhatIf` |

**Usage:**
```powershell
.\Remediate-NonCompliantResources-BySeverity.ps1 -Severity High
.\Remediate-NonCompliantResources-BySeverity.ps1 -Severity Critical -WhatIf
.\Remediate-NonCompliantResources-BySeverity.ps1 -Severity All -ExportReportOnly

.\Remediate-NonCompliantResources-MultipleMGs.ps1 -ManagementGroupIds "mg-1", "mg-2" -Severity High
```

---

#### Category: Policy Assignment (1 Script)

| Script | Description | Parameters |
|--------|-------------|------------|
| `Assign-CommonSecurityPolicies.ps1` | Bulk assign security policies | `-ManagementGroupId`, `-SubscriptionIds`, `-WhatIf`, `-Location` |

**Usage:**
```powershell
# At Management Group level
.\Assign-CommonSecurityPolicies.ps1 -ManagementGroupId "your-mg-id"

# At Subscription level
.\Assign-CommonSecurityPolicies.ps1 -SubscriptionIds "sub-id-1", "sub-id-2"

# Dry run
.\Assign-CommonSecurityPolicies.ps1 -ManagementGroupId "your-mg-id" -WhatIf

# With specific location
.\Assign-CommonSecurityPolicies.ps1 -ManagementGroupId "your-mg-id" -Location "eastus"
```

⚠️ **Note:** Update the Policy IDs in the script with your organization's actual policy definition IDs.

---

## Master Runners

### Run-AllAutoFix.ps1

Master script that executes all 41 auto-remediation scripts in logical order.

**Syntax:**
```powershell
.\Run-AllAutoFix.ps1 [-WhatIf] [-SkipSummary]
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `-WhatIf` | Switch | Dry run - shows what would be done without making changes |
| `-SkipSummary` | Switch | Skip generating summary CSV file |

**Output:**
- Console progress with color-coded status
- Summary CSV file: `AutoRemediation_Summary_YYYYMMDD_HHMMSS.csv`

**Execution Order:**
1. Storage (5 scripts)
2. Key Vault (4 scripts)
3. Microsoft Defender (1 script)
4. Identity & RBAC (7 scripts)
5. App Services (8 scripts)
6. API Management (2 scripts)
7. SQL & PostgreSQL (5 scripts)
8. Networking & VMs (4 scripts)
9. Others (1 script)

---

### Run-AllPolicyComplianceTools.ps1

Master script that orchestrates the complete compliance workflow.

**Syntax:**
```powershell
.\Run-AllPolicyComplianceTools.ps1 [-WhatIf] [-ExportAllReports] [-ManagementGroupId <string>] [-Severity <string>]
```

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-WhatIf` | Switch | - | Dry run mode |
| `-ExportAllReports` | Switch | - | Export all reports to Excel |
| `-ManagementGroupId` | String | "" | Target specific Management Group |
| `-Severity` | String | "High" | Severity filter (Critical, High, Medium, Low) |

**Workflow:**
1. Export Management Group Compliance Report
2. Export Non-Compliant Resources with Remediation Links
3. Run Severity-Based Remediation
4. Run Bulk Policy Assignment

---

## Common Parameters

All scripts support these standard parameters:

| Parameter | Type | Description |
|-----------|------|-------------|
| `-WhatIf` | Switch | Preview mode - shows what would happen without making changes |
| `-Verbose` | Switch | Detailed output |
| `-Debug` | Switch | Debug information |
| `-ErrorAction` | String | How to handle errors (Continue, Stop, SilentlyContinue) |

---

## Configuration Notes

### Sensitive Parameters

Some scripts require sensitive credentials:

| Script | Parameter | Recommendation |
|--------|------------|-----------------|
| `Fix-SQLDatabaseSymmetricKeyAES.ps1` | `-SqlAdminPassword` | Use Azure Key Vault references or service principals instead of plain passwords |
| `Assign-CommonSecurityPolicies.ps1` | Policy IDs | Update with your organization's actual policy definition IDs |

### Scope Configuration

| Scope Type | When to Use |
|------------|-------------|
| Subscription | Single subscription environments |
| Management Group | Multi-subscription/enterprise environments |

To find your Management Group ID:
```powershell
Get-AzManagementGroup | Select-Object Name, DisplayName
```

---

## Troubleshooting

### Common Issues

#### Issue: "Run-AllAutoFix.ps1 -WhatIf shows all scripts as Missing"
**Solution:** Ensure you're running the script from the correct directory:
```powershell
cd "Auto Remediation Azure Security Recommendations"
.\Run-AllAutoFix.ps1 -WhatIf
```

#### Issue: "You must call 'Connect-AzAccount' before calling any other cmdlets"
**Solution:** Authenticate first:
```powershell
Connect-AzAccount
```

#### Issue: "Insufficient privileges to complete the operation"
**Solution:** Verify your role assignments. Required permissions:
- **Owner**, **Contributor**, or **User Access Administrator** at the target scope

#### Issue: "Module 'Microsoft.Graph.Users' not found"
**Solution:** Install the required module:
```powershell
Install-Module Microsoft.Graph.Users -Scope CurrentUser -Force
```

---

## Best Practices

### Before Running in Production

1. **Always run with `-WhatIf` first** to preview changes
2. **Test on non-production subscriptions** first
3. **Review individual scripts** for specific resource targeting
4. **Backup configuration** before making bulk changes
5. **Document changes** for compliance audit trail

### Recommended Execution Order

1. Run `Run-AllPolicyComplianceTools.ps1` with `-ExportReportOnly` to assess current state
2. Run `Run-AllAutoFix.ps1` with `-WhatIf` to preview auto-remediation
3. Execute auto-remediation in phases (by category)
4. Re-run policy compliance to verify improvements

### Frequency

| Component | Recommended Frequency |
|-----------|----------------------|
| Auto-Remediation | Weekly or after significant deployments |
| Policy Compliance Reports | Daily or weekly |
| Identity Cleanup | Monthly |

---

## File Structure

```
Azure Security Auto-Remediation Toolkit/
├── Auto Remediation Azure Security Recommendations/
│   ├── Run-AllAutoFix.ps1                    # Master runner
│   ├── Fix-*.ps1                            # 45 individual fix scripts
│   └── (Readme - individual script headers)
│
└── Azure Policy Compliance & Remediation/
    ├── Run-AllPolicyComplianceTools.ps1     # Master runner
    ├── Export-*.ps1                         # 3 export scripts
    ├── Remediate-*.ps1                      # 5 remediation scripts
    ├── Assign-*.ps1                         # 1 policy assignment script
    ├── Get-*.ps1                            # 1 summary script
    └── Readme.md                            # This file
```

---

## Support and Maintenance

### Checking Script Version

Each script header contains version information:
```powershell
Get-Content .\Run-AllAutoFix.ps1 | Select-String "Version:"
```

### Updating the Toolkit

1. Download latest version
2. Compare script versions
3. Test in non-production environment
4. Update production workflow

---

*Document Version: 1.0*
*Last Updated: 2026-05-08*
*Compatible with: Azure PowerShell Az Module 5.9.0+*