using Microsoft.EntityFrameworkCore;
using Npgsql;

namespace MusicAntiBlur.Api.Http;

public static class DbConstraintMapper
{
    public static ApiException ToApiException(DbUpdateException ex)
    {
        if (ex.InnerException is not PostgresException pg)
        {
            return new ApiException(503, "dependency_unavailable", "Database is unavailable.");
        }

        if (pg.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            return MapUnique(pg.ConstraintName);
        }

        if (pg.SqlState == PostgresErrorCodes.CheckViolation)
        {
            return MapCheck(pg.ConstraintName);
        }

        return new ApiException(503, "dependency_unavailable", "Database is unavailable.");
    }

    private static ApiException MapUnique(string? constraint)
    {
        var name = constraint ?? "";
        if (name.Contains("login", StringComparison.OrdinalIgnoreCase))
        {
            return Taken("login");
        }

        if (name.Contains("email", StringComparison.OrdinalIgnoreCase) ||
            name.Contains("pending_email", StringComparison.OrdinalIgnoreCase))
        {
            return Taken("email");
        }

        if (name.Contains("hash", StringComparison.OrdinalIgnoreCase))
        {
            return new ApiException(503, "dependency_unavailable", "Could not allocate a unique token.");
        }

        return new ApiException(409, "identifier_taken", "Identifier is already taken.");
    }

    private static ApiException MapCheck(string? constraint)
    {
        var name = constraint ?? "";
        var errors = new Dictionary<string, string[]>(StringComparer.Ordinal);
        if (name.Contains("login", StringComparison.OrdinalIgnoreCase))
        {
            errors["login"] = ["login_format"];
        }
        else if (name.Contains("email", StringComparison.OrdinalIgnoreCase))
        {
            errors["email"] = ["email_format"];
        }
        else if (name.Contains("quality", StringComparison.OrdinalIgnoreCase))
        {
            errors["preferredQuality"] = ["preferred_quality"];
        }

        return new ApiException(400, "validation_failed", "Validation failed.", errors.Count == 0 ? null : errors);
    }

    private static ApiException Taken(string field) =>
        new(409, "identifier_taken", "Identifier is already taken.",
            new Dictionary<string, string[]> { [field] = ["identifier_taken"] });
}
