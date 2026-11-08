using MusicAntiBlur.Api.Catalog;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public sealed class AdminCatalogTests
{
    [Theory]
    [InlineData("ready", new[] { "ready", "ready" }, "ready")]
    [InlineData("ready", new[] { "ready", "failed" }, "failed")]
    [InlineData("failed", new string[0], "failed")]
    [InlineData("processing", new[] { "pending" }, "processing")]
    [InlineData("uploading", new string[0], "processing")]
    [InlineData("ready", new[] { "ready", "processing" }, "processing")]
    public void Summarize_picks_worst_state(string upload, string[] renditions, string expected) =>
        Assert.Equal(expected, AdminCatalogService.Summarize(upload, renditions));

    [Fact]
    public void Default_retention_is_six_months() =>
        Assert.Equal(180, new CatalogOptions().DeletedRetentionDays);
}
