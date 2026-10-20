// Phase 0 infrastructure: Automation Account + system-assigned Managed Identity,
// Log Analytics workspace, and an evidence Storage Account.
//
// NOT VALIDATED: there's no Bicep compiler or Azure CLI available in the environment
// this was authored in, so this has not been run through `az bicep build` or a
// what-if deployment. Treat it as a strong starting draft, not a tested artifact --
// run `az deployment group what-if` before applying it for real, and check the
// current API versions against Microsoft Learn since these move.
//
// Deploy scope: resource group. Pick (or create) the RG that will hold Phase 0's
// shared infrastructure -- this is NOT per-subscription, it's one shared account
// used across whichever subscriptions the Automation identity is granted the
// custom role on (see custom-role.bicep).

targetScope = 'resourceGroup'

@description('Base name used to derive resource names, e.g. "secremediation"')
param baseName string = 'secremediation'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Evidence retention in days for the Storage Account lifecycle policy')
param evidenceRetentionDays int = 2555 // ~7 years; adjust to your actual SOC 2 / audit requirement

@description('Log Analytics workspace retention in days')
param logAnalyticsRetentionDays int = 730

var automationAccountName = '${baseName}-automation'
var logAnalyticsName = '${baseName}-logs'
var storageAccountName = toLower(replace('${baseName}evid${uniqueString(resourceGroup().id)}', '-', ''))

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
  }
}

resource automationAccount 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'Basic'
    }
  }
}

// Diagnostic setting: send Automation job logs to the same Log Analytics workspace
// used for evidence trend queries.
resource automationDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-logAnalytics'
  scope: automationAccount
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'JobLogs'
        enabled: true
      }
      {
        category: 'JobStreams'
        enabled: true
      }
    ]
  }
}

resource evidenceStorage 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_GRS' // geo-redundant: evidence should survive a regional incident
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: evidenceStorage
  name: 'default'
}

resource evidenceContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'evidence'
  properties: {
    publicAccess: 'None'
  }
}

// WORM (immutability) so evidence can't be altered after the fact -- this matters
// for the SOC 2 story specifically. VERIFY this resource type/API version and the
// unlock/extend workflow against current Microsoft Learn docs before relying on it;
// immutability policy behavior (locked vs unlocked state, allowed extensions) is the
// kind of platform detail I'd want you to double-check rather than take on my word.
resource immutabilityPolicy 'Microsoft.Storage/storageAccounts/blobServices/containers/immutabilityPolicies@2023-01-01' = {
  parent: evidenceContainer
  name: 'default'
  properties: {
    immutabilityPeriodSinceCreationInDays: evidenceRetentionDays
  }
}

output automationAccountName string = automationAccount.name
output automationAccountPrincipalId string = automationAccount.identity.principalId
output logAnalyticsWorkspaceId string = logAnalytics.id
output evidenceStorageAccountName string = evidenceStorage.name
output evidenceContainerUrl string = '${evidenceStorage.properties.primaryEndpoints.blob}evidence'
