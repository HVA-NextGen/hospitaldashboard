targetScope = 'resourceGroup'

@description('Azure region approved for this fictional hospital demo.')
@allowed(['swedencentral'])
param location string = 'swedencentral'

@description('Non-sensitive deployment owner label for resource tags.')
@minLength(1)
@maxLength(64)
param deployedBy string = 'hospital-dashboard'

@description('Days to keep logs and telemetry. 30 days is included in the ingestion price.')
@minValue(30)
@maxValue(90)
param retentionInDays int = 30

var suffix = uniqueString(resourceGroup().id)
var tags = {
  workload: 'hospital-dashboard'
  environment: 'demo'
  'deployed-by': deployedBy
  data: 'synthetic-only'
}

// One workspace holds container logs and Application Insights data.
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: 'log-hospital-demo-swc-001'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    // A hard daily limit bounds the cost if something starts logging heavily.
    // When the limit is reached, collection stops until the next day.
    workspaceCapping: {
      dailyQuotaGb: json('0.2')
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-hospital-demo-swc-001'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    IngestionMode: 'LogAnalytics'
  }
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
    // Container console and system logs go to the workspace for queryable history.
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
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
output logAnalyticsName string = logAnalyticsWorkspace.name
output applicationInsightsName string = applicationInsights.name
