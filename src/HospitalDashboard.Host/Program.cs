using Microsoft.AspNetCore.ResponseCompression;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHealthChecks();
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
