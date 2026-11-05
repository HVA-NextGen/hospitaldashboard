targetScope = 'resourceGroup'

@description('Azure region approved for this fictional hospital demo.')
@allowed(['swedencentral'])
param location string = 'swedencentral'

@description('Non-sensitive deployment owner label for resource tags.')
@minLength(1)
@maxLength(64)
param deployedBy string = 'hospital-dashboard'

var suffix = uniqueString(resourceGroup().id)
var tags = {
  workload: 'hospital-dashboard'
  environment: 'demo'
  'deployed-by': deployedBy
  data: 'synthetic-only'
}

// Keep the registry private to authenticated clients; no admin passwords.
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-11-01' = {
  name: 'crhospitaldemoswc001${suffix}'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    policies: {
      azureADAuthenticationAsArmPolicy: {
        status: 'enabled'
      }
    }
  }
}

resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-hospital-demo-swc-001'
  location: location
  tags: tags
}

var acrPullRole = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
resource registryPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, pullIdentity.id, acrPullRole)
  scope: containerRegistry
  properties: {
    roleDefinitionId: acrPullRole
    principalId: pullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerEnvironment 'Microsoft.App/managedEnvironments@2026-07-01' = {
  name: 'cae-hospital-demo-swc-001'
  location: location
  tags: tags
  properties: {
    // Omit appLogsConfiguration: no retained log workspace is provisioned.
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output registryName string = containerRegistry.name
output registryServer string = containerRegistry.properties.loginServer
output identityName string = pullIdentity.name
output environmentName string = containerEnvironment.name
