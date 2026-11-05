#requires -Version 7.0
[CmdletBinding()]
param(
    [string] $SubscriptionId = 'aa8e5073-bda3-45ad-a772-7c5989954f8e',
    [string] $ResourceGroup = 'rg-hospital-dashboard',
    [string] $Location = 'swedencentral',
    [string] $DeployedBy = 'hospital-dashboard',
    [switch] $ApproveDeployment,
    [switch] $Preview,
    [switch] $UseSdkContainerBuild,
    # Optional, off by default: each test run costs money and wakes the app. See the README.
    [switch] $EnableAvailabilityTest,
    [string] $AlertEmail = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Azure {
    param([string[]] $Arguments)
    $result = & az @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Azure CLI failed: az $($Arguments -join ' ')" }
    return $result
}

function Invoke-Docker {
    param([string[]] $Arguments)
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker failed: docker $($Arguments -join ' ')" }
}

if ($Location -ne 'swedencentral') { throw 'Only the approved Sweden Central region is supported.' }
if (-not $Preview -and -not $ApproveDeployment) {
    throw 'Provisioning requires explicit approval. Review costs and run with -ApproveDeployment, or inspect with -Preview.'
}

$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $target = Invoke-Azure -Arguments @('group', 'show', '--subscription', $SubscriptionId, '--name', $ResourceGroup, '-o', 'json') | ConvertFrom-Json
    if ($target.location -ne $Location) { throw 'Resource group location differs from the approved region.' }
    Write-Host "Target: $SubscriptionId / $ResourceGroup / $Location"
    $common = @('--subscription', $SubscriptionId, '--resource-group', $ResourceGroup)
    $parameters = @('--parameters', "location=$Location", "deployedBy=$DeployedBy")
    if ($Preview) {
        Invoke-Azure (@('deployment', 'group', 'what-if') + $common + @('--template-file', 'infra/main.bicep') + $parameters)
        return
    }

    Invoke-Docker -Arguments @('info', '--format', '{{.ServerVersion}}')
    Invoke-Azure (@('deployment', 'group', 'validate') + $common + @('--template-file', 'infra/main.bicep') + $parameters + @('--only-show-errors', '-o', 'none'))
    $base = Invoke-Azure (@('deployment', 'group', 'create') + $common + @('--name', 'hospital-foundation', '--template-file', 'infra/main.bicep') + $parameters + @('--only-show-errors', '-o', 'json')) | ConvertFrom-Json
    $registry = $base.properties.outputs.registryName.value
    $server = $base.properties.outputs.registryServer.value
    $tag = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $image = "$server/hospitaldashboard:$tag"
    Invoke-Azure -Arguments @('acr', 'login', '--subscription', $SubscriptionId, '--name', $registry)
    if ($UseSdkContainerBuild) {
        # Host SDK uses the host's trusted NuGet connection instead of Docker's network.
        & dotnet publish 'src/HospitalDashboard.Host/HospitalDashboard.Host.csproj' -c Release --os linux --arch x64 /t:PublishContainer "-p:ContainerRepository=hospitaldashboard" "-p:ContainerImageTag=$tag"
        if ($LASTEXITCODE -ne 0) { throw 'SDK container publishing failed.' }
        Invoke-Docker -Arguments @('tag', "hospitaldashboard:$tag", $image)
    }
    else {
        Invoke-Docker -Arguments @('build', '--platform', 'linux/amd64', '--tag', $image, '.')
    }
    Invoke-Docker -Arguments @('push', $image)
    # Deploy by digest so a later tag change cannot alter this revision's image.
    $digest = Invoke-Azure -Arguments @('acr', 'repository', 'show', '--subscription', $SubscriptionId, '--name', $registry, '--image', "hospitaldashboard:$tag", '--query', 'digest', '-o', 'tsv')
    if ($digest -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Registry returned an invalid image digest.' }
    $immutableImage = "$server/hospitaldashboard@$digest"
    $appParameters = $parameters + @("image=$immutableImage", "enableAvailabilityTest=$($EnableAvailabilityTest.IsPresent.ToString().ToLowerInvariant())")
    if (-not [string]::IsNullOrWhiteSpace($AlertEmail)) { $appParameters += "alertEmail=$AlertEmail" }
    Invoke-Azure (@('deployment', 'group', 'validate') + $common + @('--template-file', 'infra/app.bicep') + $appParameters + @('--only-show-errors', '-o', 'none'))
    $app = Invoke-Azure (@('deployment', 'group', 'create') + $common + @('--name', 'hospital-app', '--template-file', 'infra/app.bicep') + $appParameters + @('--only-show-errors', '-o', 'json')) | ConvertFrom-Json
    $url = $app.properties.outputs.appUrl.value
    $health = Invoke-WebRequest "$url/healthz" -TimeoutSec 120
    if ($health.StatusCode -ne 200 -or $health.Content.Trim() -ne 'Healthy') { throw "Health verification failed: $url/healthz" }
    $page = Invoke-WebRequest $url -TimeoutSec 120
    if ($page.StatusCode -ne 200 -or $page.Content -notmatch 'lang="fi"') { throw "Application verification failed: $url" }
    Write-Host "Verified public dashboard: $url"
    Write-Host "Image: $immutableImage"
    if ($env:GITHUB_STEP_SUMMARY) {
        Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value "### Deployed`n- Dashboard: $url`n- Image: ``$immutableImage``"
    }
}
finally {
    Pop-Location
}
