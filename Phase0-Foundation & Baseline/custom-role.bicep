// Deploys the least-privilege custom role (same actions as
// Phase1-SafeAutoRemediation/RBAC-Phase1-CustomRole.json, expressed as a deployable
// role definition) and assigns it to the Automation Account's managed identity.
//
// NOT VALIDATED -- see the note at the top of main.bicep. Role definition/assignment
// deployments are also eventually-consistent; if the role assignment deployment fails
// with "role definition not found", wait a minute and redeploy just this file.
//
// Deploy at SUBSCRIPTION scope (not resource group), since role definitions with a
// subscription-wide assignable scope must be created there:
//   az deployment sub create --location <region> --template-file custom-role.bicep \
//     --parameters automationAccountPrincipalId=<from main.bicep output>

targetScope = 'subscription'

@description('Principal ID of the Automation Account system-assigned identity (main.bicep output)')
param automationAccountPrincipalId string

@description('Scope the role is assignable at -- a management group ID or this subscription. Defaults to this subscription; change to a management group scope if you manage multiple subscriptions centrally.')
param assignableScope string = subscription().id

var roleName = 'Phase1 Safe Auto-Remediation Operator'
var roleDefName = guid(subscription().id, roleName)

resource customRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: roleDefName
  properties: {
    roleName: roleName
    description: 'Least-privilege role for the auto-remediation Managed Identity: read/write on Storage/KeyVault/Web-Function/Defender pricing, tag read/write, and subscription/resource-group read for environment-tag resolution. Deliberately excludes Contributor and Microsoft.Authorization/* actions.'
    type: 'CustomRole'
    permissions: [
      {
        actions: [
          'Microsoft.Storage/storageAccounts/read'
          'Microsoft.Storage/storageAccounts/write'
          'Microsoft.KeyVault/vaults/read'
          'Microsoft.KeyVault/vaults/write'
          'Microsoft.Web/sites/read'
          'Microsoft.Web/sites/write'
          'Microsoft.Web/sites/config/read'
          'Microsoft.Web/sites/config/write'
          'Microsoft.Security/pricings/read'
          'Microsoft.Security/pricings/write'
          'Microsoft.Security/assessments/read'
          'Microsoft.Authorization/policyAssignments/read'
          'Microsoft.PolicyInsights/policyStates/queryResults/action'
          'Microsoft.Resources/tags/read'
          'Microsoft.Resources/tags/write'
          'Microsoft.Resources/subscriptions/read'
          'Microsoft.Resources/subscriptions/resourceGroups/read'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
    assignableScopes: [
      assignableScope
    ]
  }
}

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(assignableScope, automationAccountPrincipalId, roleDefName)
  properties: {
    roleDefinitionId: customRole.id
    principalId: automationAccountPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output roleDefinitionId string = customRole.id
