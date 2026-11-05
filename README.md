# Kaitajärven keskussairaala

A Finnish-language, live **fictional hospital dashboard** for the invented Kaitajärven hyvinvointialue. All counts, wards, trends, staffing and alerts are synthetic. **No patient data. Not a clinical decision tool.**

## Run locally

Requires .NET 10 SDK.

```powershell
dotnet run --project src\HospitalDashboard.Host
```

Open the localhost URL printed by ASP.NET Core. The Blazor WebAssembly client runs in the browser; the ASP.NET Core host only serves assets and `/healthz`. No database, authentication, cookies, external data feeds or SignalR connection.

```powershell
dotnet test HospitalDashboard.slnx -c Release
docker build --tag hospitaldashboard:local .
docker run --rm --name hospital-dashboard-local -p 8080:8080 hospitaldashboard:local
```

Open `http://localhost:8080`. Docker Desktop must be running in Linux-container mode.

## Demo behavior

- Seven sections: bed occupancy, emergency queue/wait, staffing, operating theatres, equipment, operational alerts and occupancy trends.
- Browser state updates every five seconds. Each viewer has an independent simulation; reload starts a new one. Background tabs may throttle timers; resuming advances once, without replaying missed ticks.
- A ward filter scopes beds, staffing, ward alerts and trends. ED, theatres, equipment and hospital-wide alerts always remain explicitly labeled **Koko sairaala**.
- The chart starts with 60 minutes of generated history, then keeps up to 720 samples / one hour of rolling session data. History is synthetic and disappears on reload.
- Times use `Europe/Helsinki` and Finnish formatting. No data leaves the browser during simulation.
- Demo occupancy boundaries: attention at 85%, critical at 95%. Staffing below its fictional target creates an attention status. ED wait creates attention at 45 minutes and critical at 60 minutes. These are demonstration settings, not clinical guidance.
- The UI is read-only except for ward filtering; no pause, reset or alert-acknowledgement controls.
- The dashboard has no prominent demo banner or explanatory demo panel. A discreet footer identifies the fictional hospital and synthetic data.

## Structure

| Location | Purpose |
|---|---|
| `src/HospitalDashboard.Client` | Finnish Razor dashboard, responsive CSS, client lifecycle |
| `src/HospitalDashboard.Core` | Reproducible simulation, invariants, filtering and derived alerts |
| `src/HospitalDashboard.Host` | Static asset delivery, compression, health checks |
| `tests/HospitalDashboard.Tests` | Simulation and host integration tests |
| `infra` | Resource-group-scoped Bicep, foundation then application |
| `scripts/deploy.ps1` | Explicitly approved local deployment |
| `.github/workflows/ci.yml` | Build/test/publish/container build on pushes and pull requests |

CI does **not** deploy to Azure and needs no Azure credentials.

## Azure hosting

Target: subscription `aa8e5073-bda3-45ad-a772-7c5989954f8e`, existing resource group `rg-hospital-dashboard`, region `swedencentral`.

Resources:
- Container Apps Consumption environment `cae-hospital-demo-swc-001`.
- Container App `ca-hospital-demo-swc-001`, public HTTPS, non-root Linux container, 0.25 vCPU / 0.5 GiB, **0–1 replicas**, health probes.
- Azure Container Registry Basic `crhospitaldemoswc001<resource-group-derived suffix>`, authenticated access only, admin user disabled.
- Managed identity `id-hospital-demo-swc-001`, scoped `AcrPull` permission. No registry passwords in templates or source.

The app is deployed by image digest, not a mutable `latest` tag. The registry uses its authenticated public endpoint (Basic does not offer a private endpoint). No VNet, database, Application Insights or retained Log Analytics workspace is provisioned. Use Container Apps live logs for troubleshooting.

Scale-to-zero can delay the initial page load. An already-loaded browser continues simulating without polling the host, even after the host scales down.

### Cost

Sweden Central public retail prices checked during planning:
- ACR Basic: about **US$5 per 30 days**, even when the app is idle.
- Active compute at the configured size: about **US$0.027/hour** before grants.
- Requests: US$0.40/million before grants.

Light demo use may cost roughly **US$5–10/month**, but this is **not a spending cap**. Continuous active compute for 730 hours is about US$19.71 plus the registry before grants. Subscription-shared free allowances may already be consumed. Transfer, storage overages, tax and optional later-added monitoring are extra. Check current prices before deployment.

### Deployment (separate approval required)

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

The tests cover deterministic seeds, bounded long-running simulation, reconciled counts, ward selection, threshold boundaries, history expiry, health responses, static boot assets and missing-asset behavior. Browser checks should verify multiple updates, independent sessions, reset-on-reload, filtering, mobile layout and no simulation network polling.
