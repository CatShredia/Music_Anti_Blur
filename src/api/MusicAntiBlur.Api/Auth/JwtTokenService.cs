using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.IdentityModel.Tokens;
using MusicAntiBlur.Api.Data.Entities;

namespace MusicAntiBlur.Api.Auth;

public sealed class JwtTokenService(IConfiguration config)
{
    public const int AccessTtlMinutes = 15;
    public const int RefreshTtlDays = 30;

    public (string Token, DateTimeOffset ExpiresAt) IssueAccess(User user)
    {
        var key = config["Jwt:Key"] ?? throw new InvalidOperationException("Jwt:Key is missing.");
        var issuer = config["Jwt:Issuer"] ?? "music-anti-blur";
        var audience = config["Jwt:Audience"] ?? "music-anti-blur";
        var expires = DateTimeOffset.UtcNow.AddMinutes(AccessTtlMinutes);
        var creds = new SigningCredentials(
            new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)),
            SecurityAlgorithms.HmacSha256);

        var jwt = new JwtSecurityToken(
            issuer,
            audience,
            [
                new Claim(JwtRegisteredClaimNames.Sub, user.Id.ToString("D")),
                new Claim(ClaimTypes.NameIdentifier, user.Id.ToString("D")),
                new Claim(ClaimTypes.Role, user.Role)
            ],
            expires: expires.UtcDateTime,
            signingCredentials: creds);

        return (new JwtSecurityTokenHandler().WriteToken(jwt), expires);
    }
}
