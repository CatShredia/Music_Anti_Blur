using Microsoft.EntityFrameworkCore;
using MusicAntiBlur.Api.Data.Entities;

namespace MusicAntiBlur.Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<UserSettings> UserSettings => Set<UserSettings>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<PasswordResetToken> PasswordResetTokens => Set<PasswordResetToken>();
    public DbSet<EmailVerificationToken> EmailVerificationTokens => Set<EmailVerificationToken>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.HasPostgresExtension("pgcrypto");
        modelBuilder.HasPostgresExtension("pg_trgm");

        modelBuilder.Entity<User>(e =>
        {
            e.ToTable("users", t =>
            {
                t.HasCheckConstraint("ck_users_identifier", "login IS NOT NULL OR email IS NOT NULL");
                t.HasCheckConstraint("ck_users_role", "role IN ('user', 'admin')");
                t.HasCheckConstraint("ck_users_email_normalized", "email IS NULL OR email = lower(btrim(email))");
                t.HasCheckConstraint("ck_users_verified_email", "email_verified_at IS NULL OR email IS NOT NULL");
                t.HasCheckConstraint("ck_users_login_format", "login IS NULL OR login ~ '^[a-zA-Z0-9_.-]{3,32}$'");
            });
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.Role).HasDefaultValue("user");
            e.HasIndex(x => x.Email).HasDatabaseName("ux_users_email_lower").IsUnique()
                .HasFilter("email IS NOT NULL");
            e.HasIndex(x => x.Login).HasDatabaseName("ux_users_login_lower").IsUnique()
                .HasFilter("login IS NOT NULL");
            e.HasOne(x => x.Settings).WithOne(x => x.User).HasForeignKey<UserSettings>(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<UserSettings>(e =>
        {
            e.ToTable("user_settings", t =>
            {
                t.HasCheckConstraint("ck_settings_quality", "preferred_quality IN ('auto', 'aac_128', 'aac_256', 'src')");
            });
            e.HasKey(x => x.UserId);
            e.Property(x => x.PreferredQuality).HasDefaultValue("auto");
        });

        modelBuilder.Entity<RefreshToken>(e =>
        {
            e.ToTable("refresh_tokens", t =>
            {
                t.HasCheckConstraint("ck_refresh_expiry", "expires_at > created_at");
                t.HasCheckConstraint("ck_refresh_revoked", "revoked_at IS NULL OR revoked_at >= created_at");
            });
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.HasIndex(x => x.TokenHash).IsUnique().HasDatabaseName("ux_refresh_tokens_hash");
            e.HasIndex(x => x.UserId).HasDatabaseName("ix_refresh_tokens_user");
            e.HasIndex(x => new { x.UserId, x.DeviceId }).HasDatabaseName("ix_refresh_tokens_device");
            e.HasIndex(x => x.FamilyId).HasDatabaseName("ix_refresh_tokens_family");
            e.HasIndex(x => x.ExpiresAt).HasDatabaseName("ix_refresh_tokens_expiry");
            e.HasOne(x => x.User).WithMany(x => x.RefreshTokens).HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Parent).WithMany().HasForeignKey(x => x.ParentTokenId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<PasswordResetToken>(e =>
        {
            e.ToTable("password_reset_tokens", t =>
            {
                t.HasCheckConstraint("ck_reset_expiry", "expires_at > created_at");
                t.HasCheckConstraint("ck_reset_used", "used_at IS NULL OR used_at >= created_at");
                t.HasCheckConstraint("ck_reset_invalidated", "invalidated_at IS NULL OR invalidated_at >= created_at");
                t.HasCheckConstraint("ck_reset_terminal", "used_at IS NULL OR invalidated_at IS NULL");
            });
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.HasIndex(x => x.TokenHash).IsUnique().HasDatabaseName("ux_password_reset_hash");
            e.HasIndex(x => x.UserId).HasDatabaseName("ix_password_reset_user");
            e.HasIndex(x => x.ExpiresAt).HasDatabaseName("ix_password_reset_expiry");
            e.HasOne(x => x.User).WithMany(x => x.PasswordResetTokens).HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<EmailVerificationToken>(e =>
        {
            e.ToTable("email_verification_tokens", t =>
            {
                t.HasCheckConstraint("ck_evt_email", "pending_email = lower(btrim(pending_email))");
                t.HasCheckConstraint("ck_evt_purpose", "purpose IN ('register', 'bind')");
                t.HasCheckConstraint("ck_evt_expiry", "expires_at > created_at");
                t.HasCheckConstraint("ck_evt_used", "used_at IS NULL OR used_at >= created_at");
                t.HasCheckConstraint("ck_evt_invalidated", "invalidated_at IS NULL OR invalidated_at >= created_at");
                t.HasCheckConstraint("ck_evt_terminal", "used_at IS NULL OR invalidated_at IS NULL");
            });
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.HasIndex(x => x.TokenHash).IsUnique().HasDatabaseName("ux_email_verification_hash");
            e.HasIndex(x => x.UserId).HasDatabaseName("ix_email_verification_user");
            e.HasIndex(x => x.ExpiresAt).HasDatabaseName("ix_email_verification_expiry");
            e.HasOne(x => x.User).WithMany(x => x.EmailVerificationTokens).HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
