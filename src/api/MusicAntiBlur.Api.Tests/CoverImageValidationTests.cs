using Microsoft.AspNetCore.Http;
using MusicAntiBlur.Api.Catalog;
using MusicAntiBlur.Api.Storage;
using Xunit;

namespace MusicAntiBlur.Api.Tests;

public sealed class CoverImageValidationTests
{
    private static readonly byte[] Jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10];
    private static readonly byte[] Png =
    [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D
    ];

    [Fact]
    public void Sniff_jpeg_and_png()
    {
        Assert.Equal("image/jpeg", CoverImageValidation.Sniff(Jpeg));
        Assert.Equal("image/png", CoverImageValidation.Sniff(Png));
        Assert.Null(CoverImageValidation.Sniff([0x00, 0x01, 0x02]));
    }

    [Fact]
    public void Read_rejects_missing_file()
    {
        var errors = CatalogValidation.NewErrors();
        Assert.Null(CoverImageValidation.Read(null, errors));
        Assert.Contains(CatalogValidation.Required, errors["file"]);
    }

    [Fact]
    public void Read_rejects_non_image()
    {
        var errors = CatalogValidation.NewErrors();
        Assert.Null(CoverImageValidation.Read(new MemoryFormFile("x.bin", [0x00, 0x01, 0x02, 0x03]), errors));
        Assert.Contains(CatalogValidation.CoverType, errors["file"]);
    }

    [Fact]
    public void Read_rejects_too_large()
    {
        var errors = CatalogValidation.NewErrors();
        var huge = new byte[CoverImageValidation.MaxBytes + 1];
        Jpeg.CopyTo(huge, 0);
        Assert.Null(CoverImageValidation.Read(new MemoryFormFile("big.jpg", huge), errors));
        Assert.Contains(CatalogValidation.FileTooLarge, errors["file"]);
    }

    [Fact]
    public void Read_accepts_jpeg()
    {
        var errors = CatalogValidation.NewErrors();
        var parsed = CoverImageValidation.Read(new MemoryFormFile("cover.jpg", Jpeg), errors);
        Assert.Empty(errors);
        Assert.NotNull(parsed);
        Assert.Equal("image/jpeg", parsed!.ContentType);
        Assert.Equal(Jpeg, parsed.Bytes);
    }

    [Fact]
    public void ObjectKeys_cover_matches_docs()
    {
        var id = Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
        Assert.Equal("catalog/covers/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee", ObjectKeys.Cover(id));
    }

    private sealed class MemoryFormFile(string name, byte[] bytes) : IFormFile
    {
        public string ContentType => "application/octet-stream";
        public string ContentDisposition => $"form-data; name=file; filename={name}";
        public IHeaderDictionary Headers => new HeaderDictionary();
        public long Length => bytes.Length;
        public string Name => "file";
        public string FileName => name;

        public void CopyTo(Stream target) => target.Write(bytes);

        public Task CopyToAsync(Stream target, CancellationToken cancellationToken = default)
        {
            target.Write(bytes);
            return Task.CompletedTask;
        }

        public Stream OpenReadStream() => new MemoryStream(bytes, writable: false);
    }
}
