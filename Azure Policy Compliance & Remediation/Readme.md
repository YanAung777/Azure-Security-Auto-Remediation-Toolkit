# Azure Policy Compliance & Remediation

## Overview

This subfolder contains scripts for Azure Policy compliance reporting, non-compliant resource remediation, and bulk policy assignment. These tools work in conjunction with the auto-remediation scripts in the parent folder.

## Contents

| Script | Purpose |
|--------|---------|
| `Run-AllPolicyComplianceTools.ps1` | Master runner for the complete compliance workflow |
| `Export-ManagementGroupPolicyCompliance.ps1` | Export compliance data per Management Group |
| `Export-NonCompliantResourcesWithRemediation.ps1` | Export non-compliant resources with remediation links |
| `Export-PolicyComplianceCSV.ps1` | Export compliance data to CSV |
| `Get-PolicyComplianceSummary.ps1` | Get overall compliance summary |
| `Remediate-NonCompliantResources.ps1` | Generic remediation script |
| `Remediate-NonCompliantResources-BySeverity.ps1` | Severity-filtered remediation (Critical/High/Medium/Low) |
| `Remediate-NonCompliantResources-ByMG.ps1` | Remediation by Management Group |
| `Remediate-NonCompliantResources-MultipleMGs.ps1` | Multi-MG remediation |
| `Remediate-NonCompliantPolicies.ps1` | Assign missing security policies |
| `Assign-CommonSecurityPolicies.ps1` | Bulk assign common security policies |

---

## Master Runner: Run-AllPolicyComplianceTools.ps1

### Syntax

```powershell
.\Run-AllPolicyComplianceTools.ps1 [-WhatIf] [-ExportAllReports] [-ManagementGroupId <string>] [-Severity <string>]
```

### Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-WhatIf` | Switch | - | Dry run mode |
| `-ExportAllReports` | Switch | - | Export all reports to Excel |
| `-ManagementGroupId` | String | "" | Target specific Management Group |
| `-Severity` | String | "High" | Severity filter (Critical, High, Medium, Low) |

### Examples

```powershell
# Full compliance run (High severity)
.\Run-AllPolicyComplianceTools.ps1

# Dry run
.\Run-AllPolicyComplianceTools.ps1 -WhatIf

# Critical severity only
.\Run-AllPolicyComplianceTools.ps1 -Severity Critical

# Specific Management Group
.\Run-AllPolicyComplianceTools.ps1 -ManagementGroupId "your-mg-id" -Severity High

# Export to Excel
.\Run-AllPolicyComplianceTools.ps1 -ExportAllReports
```

### Workflow

The master runner executes in this sequence:

1. **Export Management Group Compliance Report**
   - Scans all management groups
   - Generates compliance summary per MG
   - Outputs to `PolicyComplianceReports/` folder

2. **Export Non-Compliant Resources**
   - Lists all non-compliant resources
   - Includes direct remediation links to Azure Portal
   - Supports Excel export

3. **Run Remediation by Severity**
   - Targets Critical/High by default
   - Creates remediation tasks via Azure Policy
   - Can target specific Management Group if specified

4. **Bulk Policy Assignment**
   - Assigns common security policies
   - Supports MG or Subscription level scope

---

## Export Scripts

### Export-ManagementGroupPolicyCompliance.ps1

Exports detailed compliance reports for each Management Group.

**Syntax:**
```powershell
.\Export-ManagementGroupPolicyCompliance.ps1 [-OutputPath <string>] [-ExportToExcel]
```

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-OutputPath` | String | `.\PolicyComplianceReports` | Output folder path |
| `-ExportToExcel` | Switch | - | Generate Excel file (requires ImportExcel module) |

**Output Files:**
- `ManagementGroup_PolicyCompliance_Summary_TIMESTAMP.csv`
- `ManagementGroup_PolicyCompliance_TIMESTAMP.xlsx` (with `-ExportToExcel`)
- Individual MG reports: `{MGName}_Compliance_TIMESTAMP.csv`

---

### Export-NonCompliantResourcesWithRemediation.ps1

Exports non-compliant resources with links to remediation actions.

**Syntax:**
```powershell
.\Export-NonCompliantResourcesWithRemediation.ps1 [-OutputPath <string>] [-ExportToExcel]
```

**Output Files:**
- `NonCompliantResourcesWithRemediation_TIMESTAMP.csv`
- `NonCompliantResources_TIMESTAMP.xlsx` (with `-ExportToExcel`)

**Includes:**
- Resource ID
- Policy name
- Compliance state
- Direct link to Azure Portal for remediation

---

### Export-PolicyComplianceCSV.ps1

Simple CSV export of all compliance data.

**Syntax:**
```powershell
.\Export-PolicyComplianceCSV.ps1 [-OutputPath <string>]
```

---

### Get-PolicyComplianceSummary.ps1

Quick summary of overall compliance status.

**Syntax:**
```powershell
.\Get-PolicyComplianceSummary.ps1
```

**Output:**
- Total resources
- Compliant vs Non-compliant counts
- Compliance percentage
- Top non-compliant policies

---

## Remediation Scripts

### Remediate-NonCompliantResources-BySeverity.ps1

Remediates non-compliant resources based on severity.

**Syntax:**
```powershell
.\Remediate-NonCompliantResources-BySeverity.ps1 [-Severity <string>] [-WhatIf] [-Top <int>] [-ExportReportOnly]
```

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-Severity` | String | "High" | Critical, High, Medium, Low, or All |
| `-WhatIf` | Switch | - | Dry run mode |
| `-Top` | Int | 200 | Safety limit on resources to process |
| `-ExportReportOnly` | Switch | - | Export report only, no remediation |

**Examples:**
```powershell
# Remediate High severity only
.\Remediate-NonCompliantResources-BySeverity.ps1 -Severity High

# Export report only
.\Remediate-NonCompliantResources-BySeverity.ps1 -Severity All -ExportReportOnly

# Dry run Critical severity
.\Remediate-NonCompliantResources-BySeverity.ps1 -Severity Critical -WhatIf
```

---

### Remediate-NonCompliantResources-MultipleMGs.ps1

Remediate across multiple Management Groups.

**Syntax:**
```powershell
.\Remediate-NonCompliantResources-MultipleMGs.ps1 -ManagementGroupIds <string[]>] -Severity <string>] [-WhatIf]
```

**Examples:**
```powershell
# Multi-MG remediation
.\Remediate-NonCompliantResources-MultipleMGs.ps1 -ManagementGroupIds "mg-prod", "mg-dev" -Severity High

# Dry run
.\Remediate-NonCompliantResources-MultipleMGs.ps1 -ManagementGroupIds "mg-prod" -Severity Critical -WhatIf
```

---

### Remediate-NonCompliantResources-ByMG.ps1

Remediate resources in a specific Management Group.

**Syntax:**
```powershell
.\Remediate-NonCompliantResources-ByMG.ps1 -ManagementGroupId <string>] [-WhatIf]
```

**Examples:**
```powershell
.\Remediate-NonCompliantResources-ByMG.ps1 -ManagementGroupId "mg-production"
.\Remediate-NonCompliantResources-ByMG.ps1 -ManagementGroupId "mg-production" -WhatIf
```

---

### Remediate-NonCompliantResources.ps1

Generic remediation without severity filtering.

**Syntax:**
```powershell
.\Remediate-NonCompliantResources.ps1 [-WhatIf]
```

---

### Remediate-NonCompliantPolicies.ps1

Assigns missing policy definitions to subscriptions.

**Syntax:**
```powershell
.\Remediate-NonCompliantPolicies.ps1 [-WhatIf]
```

---

## Policy Assignment Script

### Assign-CommonSecurityPolicies.ps1

Bulk assigns recommended Microsoft security policies.

**Syntax:**
```powershell
.\Assign-CommonSecurityPolicies.ps1 [-ManagementGroupId <string>] [-SubscriptionIds <string[]>] [-WhatIf] [-Location <string>]
```

**Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-ManagementGroupId` | String | "" | Management Group scope |
| `-SubscriptionIds` | String[] | @() | Subscription scope (use one or the other) |
| `-WhatIf` | Switch | - | Dry run mode |
| `-Location` | String | "eastus" | Azure region for policy assignment |

**Examples:**
```powershell
# At Management Group level
.\Assign-CommonSecurityPolicies.ps1 -ManagementGroupId "your-mg-id"

# At Subscription level
.\Assign-CommonSecurityPolicies.ps1 -SubscriptionIds "sub-xxx", "sub-yyy"

# Dry run
.\Assign-CommonSecurityPolicies.ps1 -ManagementGroupId "your-mg-id" -WhatIf
```

**Policies Assigned:**
- EnableDefenderForServers
- EnableDefenderForStorage
- EnableDefenderForAppService
- EnableDefenderForSQL
- StorageAccountRequireTLS
- KeyVaultSoftDelete
- KeyVaultPurgeProtection
- FunctionAppHTTPSOnly
- WebAppHTTPSOnly

⚠️ **Note:** Update the Policy IDs in the script with your organization's actual policy definition IDs before running.

---

## Prerequisites

### Required Permissions

| Role | Scope | Required For |
|-----|-------|-------------|
| Owner or Policy Administrator | Management Group | Assign policies |
| Owner or Contributor | Subscription | Remediation tasks |
| Reader | Management Group | Compliance reports |

### Required Modules

```powershell
# Azure PowerShell
Install-Module Az -Scope CurrentUser -Force

# For Excel export (optional)
Install-Module ImportExcel -Scope CurrentUser -Force
```

---

## Best Practices

### Before Running

1. **Always run with `-WhatIf` first**
2. **Start with `-Severity High` or `-Severity Critical`** to minimize risk
3. **Use `-ExportReportOnly`** to review affected resources before remediation
4. **Test in development subscriptions** first

### Monitoring Remediation Tasks

After running remediation scripts, monitor tasks in Azure Portal:

```
Azure Portal → Policy → Remediation
```

### Frequency

| Task | Recommended Frequency |
|------|----------------------|
| Compliance Reports | Daily |
| High/Critical Remediation | Weekly |
| Full Remediation Run | Monthly |

---

## Troubleshooting

### "No such module 'ImportExcel'"

Install the ImportExcel module:
```powershell
Install-Module ImportExcel -Scope CurrentUser -Force
```

### "Insufficient privileges to complete the operation"

Verify your role assignment:
- For MG-level operations: Owner or Policy Administrator at MG level
- For Subscription-level: Contributor or Security Admin

### Remediation tasks not starting

Check the policy assignment exists:
```powershell
Get-AzPolicyAssignment | Select-Object DisplayName, Scope
```

---

## Output Files

All export scripts create files in the `PolicyComplianceReports` folder (created automatically):

```
PolicyComplianceReports/
├── {timestamp}/
│   ├── ManagementGroup_PolicyCompliance_Summary_20260101_120000.csv
│   ├── ManagementGroup_PolicyCompliance_20260101_120000.xlsx
│   ├── NonCompliantResourcesWithRemediation_20260101_120000.csv
│   └── {MGName}_Compliance_20260101_120000.csv
└── NonCompliant_Severity_High_20260101_120000.csv
```

---

*Version: 1.0*
*Last Updated: 2026-05-08*