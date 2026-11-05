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

@description('Create an Application Insights availability test. It costs about US$0.000645 per run and each ping wakes the app, which reduces scale-to-zero savings.')
param enableAvailabilityTest bool = false

@description('Azure locations the availability test runs from. Used only when the test is enabled.')
param availabilityLocations array = [
  'emea-nl-ams-azr' // West Europe
  'emea-gb-db3-azr' // North Europe
]

@description('Seconds between availability test runs. Longer than the 5-minute scale-down delay lets the app sleep between pings.')
@allowed([300, 600, 900])
param availabilityFrequencySeconds int = 900

@description('Optional email address for the availability alert. Leave empty to skip the alert; no address is stored in the repository.')
param alertEmail string = ''

var suffix = uniqueString(resourceGroup().id)
var alertsEnabled = enableAvailabilityTest && !empty(alertEmail)
var tags = {
  workload: 'hospital-dashboard'
  environment: 'demo'
  'deployed-by': deployedBy
  data: 'synthetic-only'
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: 'crhospitaldemoswc001${suffix}'
}
resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-hospital-demo-swc-001'
}
resource containerEnvironment 'Microsoft.App/managedEnvironments@2026-07-01' existing = {
  name: 'cae-hospital-demo-swc-001'
}
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: 'appi-hospital-demo-swc-001'
}

resource containerApp 'Microsoft.App/containerApps@2026-07-01' = {
  name: 'ca-hospital-demo-swc-001'
  location: location
  tags: tags
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
      // Stored as an app secret and read through secretRef, so it never appears in plain text settings or outputs.
      secrets: [
        {
          name: 'appinsights-connection-string'
          value: applicationInsights.properties.ConnectionString
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
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'appinsights-connection-string'
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

// Optional: pings /healthz from outside Azure. Off by default because each run costs money and wakes the app.
resource availabilityTest 'Microsoft.Insights/webtests@2022-06-15' = if (enableAvailabilityTest) {
  name: 'avail-hospital-demo-swc-001'
  location: location
  tags: union(tags, {
    'hidden-link:${applicationInsights.id}': 'Resource'
  })
  kind: 'standard'
  properties: {
    SyntheticMonitorId: 'avail-hospital-demo-swc-001'
    Name: 'Dashboard health'
    Enabled: true
    Frequency: availabilityFrequencySeconds
    Timeout: 30
    Kind: 'standard'
    RetryEnabled: true
    Locations: [for locationId in availabilityLocations: {
      Id: locationId
    }]
    Request: {
      RequestUrl: 'https://${containerApp.properties.configuration.ingress.fqdn}/healthz'
      HttpVerb: 'GET'
      ParseDependentRequests: false
    }
    ValidationRules: {
      ExpectedHttpStatusCode: 200
      SSLCheck: true
      SSLCertRemainingLifetimeCheck: 7
    }
  }
}

resource alertActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (alertsEnabled) {
  name: 'ag-hospital-demo-swc-001'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'hospital'
    enabled: true
    emailReceivers: [
      {
        name: 'owner'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// Fires when every test location reports a failure within 15 minutes.
resource availabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (alertsEnabled) {
  name: 'alert-hospital-demo-swc-001'
  location: 'global'
  tags: union(tags, {
    'hidden-link:${applicationInsights.id}': 'Resource'
    'hidden-link:${availabilityTest.id}': 'Resource'
  })
  properties: {
    description: 'The public dashboard failed its availability test from all locations.'
    severity: 1
    enabled: true
    scopes: [
      availabilityTest.id
      applicationInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
      webTestId: availabilityTest.id
      componentId: applicationInsights.id
      failedLocationCount: length(availabilityLocations)
    }
    actions: [
      {
        actionGroupId: alertActionGroup.id
      }
    ]
  }
}

output appName string = containerApp.name
output appUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
output availabilityTestEnabled bool = enableAvailabilityTest
output alertEnabled bool = alertsEnabled
