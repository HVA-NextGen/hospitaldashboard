using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using HospitalDashboard.Client;
using System.Globalization;

CultureInfo.DefaultThreadCurrentCulture = CultureInfo.GetCultureInfo("fi-FI");
CultureInfo.DefaultThreadCurrentUICulture = CultureInfo.GetCultureInfo("fi-FI");

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

await builder.Build().RunAsync();
