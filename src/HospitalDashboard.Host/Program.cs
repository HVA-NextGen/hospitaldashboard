using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.AspNetCore.ResponseCompression;
using OpenTelemetry.Instrumentation.AspNetCore;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHealthChecks();

// Telemetry is sent only when Azure supplies a connection string, so local runs and tests stay silent.
if (!string.IsNullOrWhiteSpace(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    builder.Services.AddOpenTelemetry().UseAzureMonitor();
    // Container health probes and availability pings hit /healthz constantly and would dominate ingestion.
    builder.Services.Configure<AspNetCoreTraceInstrumentationOptions>(options =>
        options.Filter = context => !context.Request.Path.StartsWithSegments("/healthz"));
}

builder.Services.AddResponseCompression(options =>
{
    options.EnableForHttps = true;
    options.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat(["application/wasm", "application/octet-stream"]);
});
var app = builder.Build();

app.UseResponseCompression();
app.Use(async (context, next) =>
{
    context.Response.Headers.XContentTypeOptions = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    context.Response.Headers["Content-Security-Policy"] =
        "default-src 'self'; script-src 'self' 'wasm-unsafe-eval' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; " +
        "img-src 'self' data:; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'";
    await next();
});
app.UseBlazorFrameworkFiles();
app.UseStaticFiles();
app.MapHealthChecks("/healthz");
app.MapFallbackToFile("index.html");

app.Run();

public partial class Program;
