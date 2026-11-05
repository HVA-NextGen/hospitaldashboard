# Kaitajärven hyvinvointialue: ambulanssit ja saapuvat potilaat

A Finnish-language **fictional emergency-care dashboard** for the invented Kaitajärven hyvinvointialue. It shows ambulances on their way to Kaitajärven keskussairaala on a schematic regional map. All data is a fixed, synthetic example. **No patient data. Not a clinical decision tool.**

## Run locally

Requires .NET 10 SDK.

```powershell
dotnet run --project src\HospitalDashboard.Host
```

Open the localhost URL printed by ASP.NET Core. The Blazor WebAssembly client runs in the browser; the ASP.NET Core host only serves assets and `/healthz`. No database, authentication, cookies, external data feeds, timers or SignalR connection.

```powershell
docker build --tag hospitaldashboard:local .
docker run --rm --name hospital-dashboard-local -p 8080:8080 hospitaldashboard:local
```

Open `http://localhost:8080`. Docker Desktop must be running in Linux-container mode. If NuGet TLS fails inside Docker, see the SDK container build option under Deployment.

## What the dashboard shows

- A snapshot at a fixed time (5.11.2026 klo 20.15) from fixed data in `src/HospitalDashboard.Core/ArrivalsData.cs`. Nothing updates or moves; reloading shows the same view.
- Summary figures: ambulances heading to the hospital, the next arrival, missions today against a typical Thursday, and free units.
- A schematic SVG map with the lake, roads, settlements, ambulance stations and the hospital. Circle size shows missions started in each area today.
- Each incoming ambulance sits at its fixed progress along its road. Select one in the list (or click it on the map) to highlight its route and see its details.
- Missions per hour today against a typical Thursday, missions by area, and free units per station.
- Urgency classes A–D, with A the most urgent, are shown with the general reason for each mission. No patient details are included.
- The layout is desktop-only (minimum width 1280 px) and has no responsive or mobile rules.
- Times use Finnish formatting. A discreet footer identifies the fictional area and synthetic data.

## Structure

| Location | Purpose |
|---|---|
| `src/HospitalDashboard.Client` | Finnish Razor dashboard page and CSS |
| `src/HospitalDashboard.Core` | Static example data for the map, ambulances, stations and hourly counts |
| `src/HospitalDashboard.Host` | Static asset delivery, compression, health checks |
| `tests/HospitalDashboard.Tests` | Host integration tests |
| `infra` | Resource-group-scoped Bicep, foundation then application |
| `scripts/deploy.ps1` | Explicitly approved deployment, run locally or by the deploy workflow |
| `scripts/setup-github-oidc.ps1` | One-time Azure and GitHub setup for the deploy workflow (dry run by default) |
| `.github/workflows/ci.yml` | Build/test/publish/container build on pushes and pull requests |
| `.github/workflows/deploy.yml` | Manual deployment to Azure using OIDC |

The CI workflow does **not** deploy to Azure and needs no Azure credentials. Deployment is a separate, manually triggered workflow.

## Azure hosting

Target: subscription `aa8e5073-bda3-45ad-a772-7c5989954f8e`, existing resource group `rg-hospital-dashboard`, region `swedencentral`.

Resources:
- Container Apps Consumption environment `cae-hospital-demo-swc-001`.
- Container App `ca-hospital-demo-swc-001`, public HTTPS, non-root Linux container, 0.25 vCPU / 0.5 GiB, **0–1 replicas**, health probes.
- Azure Container Registry Basic `crhospitaldemoswc001<resource-group-derived suffix>`, authenticated access only, admin user disabled.
- Managed identity `id-hospital-demo-swc-001`, scoped `AcrPull` permission. No registry passwords in templates or source.

The app is deployed by image digest, not a mutable `latest` tag. The registry uses its authenticated public endpoint (Basic does not offer a private endpoint). No VNet, database, Application Insights or retained Log Analytics workspace is provisioned. Use Container Apps live logs for troubleshooting.

Scale-to-zero can delay the initial page load. Once loaded, the page makes no further requests, because the data is fixed in the app.

### Cost

Sweden Central public retail prices checked during planning:
- ACR Basic: about **US$5 per 30 days**, even when the app is idle.
- Active compute at the configured size: about **US$0.027/hour** before grants.
- Requests: US$0.40/million before grants.

Light demo use may cost roughly **US$5–10/month**, but this is **not a spending cap**. Continuous active compute for 730 hours is about US$19.71 plus the registry before grants. Subscription-shared free allowances may already be consumed. Transfer, storage overages, tax and optional later-added monitoring are extra. Check current prices before deployment.

### Deploying from GitHub Actions

The **Deploy to Azure** workflow (`.github/workflows/deploy.yml`) runs `scripts/deploy.ps1` on a GitHub-hosted runner. It signs in with **OIDC**, so no Azure secret is stored in GitHub.

It can only be started manually (**Actions > Deploy to Azure > Run workflow**) and:
- runs only on `main`, and only if you type `deploy` in the confirmation input;
- requires a successful **Build and test** run for the exact commit being deployed;
- uses the `azure-demo` environment, where you can require reviewers before the job starts;
- never runs two deployments at once.

One-time setup, run by someone with permission to create Entra app registrations and role assignments:

```powershell
az login --tenant e6eb6b36-75f8-4c32-94fc-953eff5c5c37
gh auth login
# Dry run: prints the plan and changes nothing.
.\scripts\setup-github-oidc.ps1
# Creates the identity, role assignments, environment and variables.
.\scripts\setup-github-oidc.ps1 -Apply
```

This creates an app registration with a federated credential that trusts **only** the `azure-demo` environment of this repository, plus `Contributor` and a restricted `Role Based Access Control Administrator` (limited to assigning `AcrPull`) on `rg-hospital-dashboard` only. It also sets the repository variables `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` and `AZURE_RESOURCE_GROUP`. These are identifiers, not secrets. Afterwards, add required reviewers to the `azure-demo` environment in GitHub settings.

The workflow builds the image on the runner with Docker, so it does not need the `-UseSdkContainerBuild` option. To remove the access later, delete the app registration (`github-hospitaldashboard-deploy`) and the `azure-demo` environment.

### Deployment from your machine (separate approval required)

Requires Azure CLI, Bicep, PowerShell 7 and Docker. Authenticate to the target tenant with access to create resources, assign managed identities/registry roles and push images. Verify regional consumption capacity and applicable policies first.

```powershell
az login --tenant e6eb6b36-75f8-4c32-94fc-953eff5c5c37
# Read-only foundation change preview; does not provision.
.\scripts\deploy.ps1 -Preview
# ONLY after reviewing and approving billable resource creation:
.\scripts\deploy.ps1 -ApproveDeployment
```

The script uses explicit subscription arguments without changing your default subscription. It validates Bicep, creates the foundation, locally builds/pushes an image, deploys the app and checks public HTML and health. It fails visibly on errors. If role propagation temporarily prevents image pulls, investigate the deployment error and rerun after permissions propagate; do not enable registry admin credentials.

If NuGet TLS fails inside Docker while restore works on the host, use `-UseSdkContainerBuild` to build the Linux image with .NET's built-in container publishing instead. This does not disable certificate validation or change the runtime configuration. For a local SDK-built image:

```powershell
dotnet publish src\HospitalDashboard.Host -c Release --os linux --arch x64 /t:PublishContainer -p:ContainerRepository=hospitaldashboard -p:ContainerImageTag=local
```

Re-running updates the same named resources with a fresh immutable image. Old registry images can accumulate; remove unused images deliberately, after checking deployed revisions.

```powershell
az containerapp show --subscription aa8e5073-bda3-45ad-a772-7c5989954f8e --resource-group rg-hospital-dashboard --name ca-hospital-demo-swc-001 --query properties.configuration.ingress.fqdn -o tsv
az containerapp logs show --subscription aa8e5073-bda3-45ad-a772-7c5989954f8e --resource-group rg-hospital-dashboard --name ca-hospital-demo-swc-001 --type console --follow
```

### Cleanup

Inspect the resource group first. Never automatically delete the existing resource group: it may later contain unrelated resources. To retire this demo, explicitly delete **only** the named Container App, its environment, its managed identity and its generated registry (registry deletion removes its images). Deleting the app alone does not stop registry charges. Check names and dependencies in Azure before confirming each removal.

## Validation

The remaining host tests cover health responses, static boot assets and missing-asset behavior. The simulation tests were removed together with the simulation. Browser checks verified the page loads without console errors, that selecting an ambulance updates the map and details, and that the page makes no background requests.
