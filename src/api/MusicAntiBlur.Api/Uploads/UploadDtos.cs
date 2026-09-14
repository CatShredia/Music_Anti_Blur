namespace MusicAntiBlur.Api.Uploads;

public sealed record InitiateUploadRequest(string? FileName, long? SizeBytes, string? ContentType, string? ChecksumSha256);

public sealed record InitiateUploadResponse(Guid GenerationId, long PartSizeBytes, int PartCount, DateTimeOffset ExpiresAt);

public sealed record UploadPartsRequest(int[]? PartNumbers);

public sealed record UploadPartUrlDto(int PartNumber, string Url, DateTimeOffset ExpiresAt);

public sealed record UploadPartsResponse(IReadOnlyList<UploadPartUrlDto> Parts);

public sealed record CompleteUploadPartDto(int PartNumber, string? ETag);

public sealed record CompleteUploadRequest(IReadOnlyList<CompleteUploadPartDto>? Parts);

public sealed record UploadAcceptedResponse(Guid GenerationId, string Status);

public sealed record UploadStatusResponse(
    Guid GenerationId,
    string Status,
    bool IsActive,
    long? SizeBytes,
    int? DurationMs,
    string? ErrorMessage);

public sealed record RenditionStatusDto(
    Guid GenerationId,
    string Code,
    string Status,
    int? BitrateKbps,
    bool IsActive,
    string? ErrorMessage);

public sealed record TranscodeRequest(Guid? GenerationId);
