targetScope = 'resourceGroup'

@description('Full immutable image reference in the registry created by main.bicep.')
@minLength(1)
@maxLength(256)
param image string

@description('Azure region approved for this demo.')
@allowed(['swedencentral'])
param location string = 'swedencentral'

@description('Non-sensitive deployment owner label for resource tags.')
@minLength(1)
@maxLength(64)
param deployedBy string = 'hospital-dashboard'

var suffix = uniqueString(resourceGroup().id)
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: 'crhospitaldemoswc001${suffix}'
}
resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-hospital-demo-swc-001'
}
resource containerEnvironment 'Microsoft.App/managedEnvironments@2026-07-01' existing = {
  name: 'cae-hospital-demo-swc-001'
}

resource containerApp 'Microsoft.App/containerApps@2026-07-01' = {
  name: 'ca-hospital-demo-swc-001'
  location: location
  tags: {
    workload: 'hospital-dashboard'
    environment: 'demo'
    'deployed-by': deployedBy
    data: 'synthetic-only'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${pullIdentity.id}': {}
    }
  }
  properties: {
    environmentId: containerEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        allowInsecure: false
        targetPort: 8080
        transport: 'auto'
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: pullIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'dashboard'
          image: image
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: 'Production'
            }
          ]
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/healthz'
                port: 8080
                scheme: 'HTTP'
              }
              periodSeconds: 5
              failureThreshold: 30
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/healthz'
                port: 8080
                scheme: 'HTTP'
              }
              periodSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/healthz'
                port: 8080
                scheme: 'HTTP'
              }
              periodSeconds: 30
              failureThreshold: 3
            }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 1
        rules: [
          {
            name: 'http'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

output appName string = containerApp.name
output appUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
