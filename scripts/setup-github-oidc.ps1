#requires -Version 7.0
<#
.SYNOPSIS
  One-time setup that lets the "Deploy to Azure" workflow sign in with OIDC (no stored secrets).

.DESCRIPTION
  Creates a Microsoft Entra app registration and service principal, a federated credential that only trusts the
  GitHub environment below, narrowly scoped role assignments on the resource group, the GitHub environment and
  the repository variables the workflow reads.

  Dry run by default: without -Apply it prints what it would do and changes nothing.
#>
[CmdletBinding()]
param(
    [string] $SubscriptionId = 'aa8e5073-bda3-45ad-a772-7c5989954f8e',
    [string] $TenantId = 'e6eb6b36-75f8-4c32-94fc-953eff5c5c37',
    [string] $ResourceGroup = 'rg-hospital-dashboard',
    [string] $Repository = 'HVA-NextGen/hospitaldashboard',
    [string] $EnvironmentName = 'azure-demo',
    [string] $AppName = 'github-hospitaldashboard-deploy',
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Native {
    param([string] $Command, [string[]] $Arguments)
    $output = & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed: $($Arguments -join ' ')" }
    return $output
}

$scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
$subject = "repo:${Repository}:environment:${EnvironmentName}"
$acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

# The infrastructure assigns AcrPull to the app's managed identity, so the deployer needs role-assignment rights.
# This condition limits that right to the AcrPull role only, instead of granting User Access Administrator.
$condition = @"
((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$acrPullRoleId})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$acrPullRoleId}))
"@.Trim()

Write-Host 'Plan:'
Write-Host "  Entra app registration : $AppName (tenant $TenantId)"
Write-Host "  Federated credential   : trusts only '$subject'"
Write-Host "  Roles on $scope"
Write-Host '    - Contributor'
Write-Host '    - Role Based Access Control Administrator, limited to assigning/removing AcrPull'
Write-Host "  GitHub environment     : $EnvironmentName in $Repository (add required reviewers in the GitHub UI)"
Write-Host '  GitHub variables       : AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, AZURE_RESOURCE_GROUP'
if (-not $Apply) {
    Write-Host ''
    Write-Host 'Dry run only. Nothing was changed. Re-run with -Apply to create these.'
    return
}

$current = Invoke-Native az @('account', 'show', '--query', '{tenant:tenantId}', '-o', 'json') | ConvertFrom-Json
if ($current.tenant -ne $TenantId) { throw "Signed in to tenant $($current.tenant), expected $TenantId. Run: az login --tenant $TenantId" }
Invoke-Native az @('group', 'show', '--subscription', $SubscriptionId, '--name', $ResourceGroup, '--query', 'name', '-o', 'tsv') | Out-Null

$app = Invoke-Native az @('ad', 'app', 'list', '--display-name', $AppName, '--query', '[0].{id:id,appId:appId}', '-o', 'json') | ConvertFrom-Json
if ($null -eq $app) {
    $app = Invoke-Native az @('ad', 'app', 'create', '--display-name', $AppName, '--query', '{id:id,appId:appId}', '-o', 'json') | ConvertFrom-Json
    Write-Host "Created app registration $($app.appId)"
}
else {
    Write-Host "Using existing app registration $($app.appId)"
}

$principalId = Invoke-Native az @('ad', 'sp', 'list', '--filter', "appId eq '$($app.appId)'", '--query', '[0].id', '-o', 'tsv')
if ([string]::IsNullOrWhiteSpace($principalId)) {
    $principalId = Invoke-Native az @('ad', 'sp', 'create', '--id', $app.appId, '--query', 'id', '-o', 'tsv')
    Write-Host 'Created service principal'
}

$credentialName = "github-$EnvironmentName"
$existingCredential = Invoke-Native az @('ad', 'app', 'federated-credential', 'list', '--id', $app.id, '--query', "[?name=='$credentialName'].name", '-o', 'tsv')
if ([string]::IsNullOrWhiteSpace($existingCredential)) {
    $credentialFile = New-TemporaryFile
    try {
        @{
            name      = $credentialName
            issuer    = 'https://token.actions.githubusercontent.com'
            subject   = $subject
            audiences = @('api://AzureADTokenExchange')
        } | ConvertTo-Json | Set-Content -Path $credentialFile -Encoding utf8
        Invoke-Native az @('ad', 'app', 'federated-credential', 'create', '--id', $app.id, '--parameters', "@$credentialFile") | Out-Null
    }
    finally {
        Remove-Item $credentialFile -Force -ErrorAction SilentlyContinue
    }
    Write-Host 'Created federated credential'
}

function Add-Role {
    param([string] $Role, [string[]] $Extra = @())
    $existing = Invoke-Native az @('role', 'assignment', 'list', '--assignee', $principalId, '--scope', $scope, '--role', $Role, '--query', 'length(@)', '-o', 'tsv')
    if ([int]$existing -gt 0) { Write-Host "Role already assigned: $Role"; return }
    Invoke-Native az (@('role', 'assignment', 'create', '--assignee-object-id', $principalId, '--assignee-principal-type', 'ServicePrincipal', '--role', $Role, '--scope', $scope) + $Extra) | Out-Null
    Write-Host "Assigned role: $Role"
}

Add-Role -Role 'Contributor'
Add-Role -Role 'Role Based Access Control Administrator' -Extra @('--condition', $condition, '--condition-version', '2.0')

Invoke-Native gh @('api', '--method', 'PUT', "repos/$Repository/environments/$EnvironmentName", '--silent') | Out-Null
Write-Host "GitHub environment ready: $EnvironmentName"
$variables = @{
    AZURE_CLIENT_ID       = $app.appId
    AZURE_TENANT_ID       = $TenantId
    AZURE_SUBSCRIPTION_ID = $SubscriptionId
    AZURE_RESOURCE_GROUP  = $ResourceGroup
}
foreach ($name in $variables.Keys) {
    Invoke-Native gh @('variable', 'set', $name, '--repo', $Repository, '--body', $variables[$name]) | Out-Null
}
Write-Host 'Repository variables set (identifiers only; no secrets were created).'
Write-Host ''
Write-Host "Next: in GitHub, open Settings > Environments > $EnvironmentName and add required reviewers."
Write-Host 'Role assignments can take a few minutes to propagate before the first deployment.'
