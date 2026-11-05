using System.Net;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;

namespace HospitalDashboard.Tests;

public sealed partial class HostTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient client;

    public HostTests(WebApplicationFactory<Program> factory)
    {
        client = factory.WithWebHostBuilder(builder => builder.UseEnvironment("Development")).CreateClient();
    }

    [Theory]
    [InlineData("/")]
    [InlineData("/dashboard")]
    public async Task HtmlRoutesServeTheFinnishApplication(string route)
    {
        var response = await client.GetAsync(route);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("text/html", response.Content.Headers.ContentType?.MediaType);
        var html = await response.Content.ReadAsStringAsync();
        Assert.Contains("lang=\"fi\"", html);
        Assert.Contains("Kaitajärven keskussairaala", html);
        Assert.Equal("nosniff", Assert.Single(response.Headers.GetValues("X-Content-Type-Options")));
    }

    [Fact]
    public async Task HealthEndpointIsNotTheSpaFallback()
    {
        var response = await client.GetAsync("/healthz");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Healthy", await response.Content.ReadAsStringAsync());
    }

    [Fact]
    public async Task ClientBootScriptAndStylesAreServedWithCorrectMimeTypes()
    {
        var html = await client.GetStringAsync("/");
        var match = BootScript().Match(html);
        Assert.True(match.Success);
        var boot = await client.GetAsync("/" + match.Groups[1].Value);
        Assert.Equal(HttpStatusCode.OK, boot.StatusCode);
        Assert.Contains(boot.Content.Headers.ContentType?.MediaType, new[] { "text/javascript", "application/javascript" });
        var css = await client.GetAsync("/css/app.css");
        Assert.Equal("text/css", css.Content.Headers.ContentType?.MediaType);
    }

    [Theory]
    [InlineData("/_framework/missing.js")]
    [InlineData("/css/missing.css")]
    public async Task MissingAssetsDoNotReturnSuccessShapedHtml(string path)
    {
        var response = await client.GetAsync(path);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [GeneratedRegex("src=\"(_framework/blazor\\.webassembly[^\\\"]*\\.js)\"")]
    private static partial Regex BootScript();
}
