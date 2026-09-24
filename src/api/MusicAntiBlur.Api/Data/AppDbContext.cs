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
    public DbSet<Artist> Artists => Set<Artist>();
    public DbSet<Album> Albums => Set<Album>();
    public DbSet<Track> Tracks => Set<Track>();
    public DbSet<CatalogUpload> CatalogUploads => Set<CatalogUpload>();
    public DbSet<TrackRendition> TrackRenditions => Set<TrackRendition>();
    public DbSet<ObjectDeletion> ObjectDeletions => Set<ObjectDeletion>();
    public DbSet<IdempotencyRecord> IdempotencyRecords => Set<IdempotencyRecord>();
    public DbSet<PlaybackState> PlaybackStates => Set<PlaybackState>();
    public DbSet<UserTrackOverride> UserTrackOverrides => Set<UserTrackOverride>();
    public DbSet<UserPrivateUpload> UserPrivateUploads => Set<UserPrivateUpload>();
    public DbSet<UserPrivateRendition> UserPrivateRenditions => Set<UserPrivateRendition>();
    public DbSet<UserTrackStat> UserTrackStats => Set<UserTrackStat>();
    public DbSet<UserPlayHistory> UserPlayHistories => Set<UserPlayHistory>();

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
                t.HasCheckConstraint("ck_users_email_length", "email IS NULL OR (char_length(email) BETWEEN 3 AND 254)");
                t.HasCheckConstraint("ck_users_password_hash", "char_length(password_hash) > 0");
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
            e.HasIndex(x => x.PendingEmail).HasDatabaseName("ux_evt_pending_email_active").IsUnique()
                .HasFilter("used_at IS NULL AND invalidated_at IS NULL AND purpose = 'bind'");
            e.HasOne(x => x.User).WithMany(x => x.EmailVerificationTokens).HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<Artist>(e =>
        {
            e.ToTable("artists");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.Name).IsRequired();
            e.Property(x => x.SortName).IsRequired();
            e.HasIndex(x => x.SortName).HasDatabaseName("ix_artists_sort_name");
            e.HasIndex(x => x.Name).HasDatabaseName("gin_artists_name").HasMethod("gin")
                .HasOperators("gin_trgm_ops");
        });

        modelBuilder.Entity<Album>(e =>
        {
            e.ToTable("albums", t =>
            {
                t.HasCheckConstraint("ck_albums_year", "year IS NULL OR year BETWEEN 1000 AND 9999");
            });
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.Title).IsRequired();
            e.HasIndex(x => x.ArtistId).HasDatabaseName("ix_albums_artist");
            e.HasIndex(x => x.Title).HasDatabaseName("gin_albums_title").HasMethod("gin")
                .HasOperators("gin_trgm_ops");
            e.HasOne(x => x.Artist).WithMany(x => x.Albums).HasForeignKey(x => x.ArtistId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<Track>(e =>
        {
            e.ToTable("tracks", t =>
            {
                t.HasCheckConstraint("ck_tracks_number", "track_number >= 1");
                t.HasCheckConstraint("ck_tracks_duration", "duration_ms IS NULL OR duration_ms > 0");
            });
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.Title).IsRequired();
            e.HasIndex(x => new { x.AlbumId, x.TrackNumber }).IsUnique()
                .HasDatabaseName("ux_tracks_album_number");
            e.HasIndex(x => x.Isrc).IsUnique().HasDatabaseName("ux_tracks_isrc")
                .HasFilter("isrc IS NOT NULL");
            e.HasIndex(x => x.ArtistId).HasDatabaseName("ix_tracks_artist");
            e.HasIndex(x => x.Title).HasDatabaseName("gin_tracks_title").HasMethod("gin")
                .HasOperators("gin_trgm_ops");
            e.HasOne(x => x.Album).WithMany(x => x.Tracks).HasForeignKey(x => x.AlbumId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Artist).WithMany(x => x.Tracks).HasForeignKey(x => x.ArtistId)
                .OnDelete(DeleteBehavior.Restrict);
        });

        modelBuilder.Entity<CatalogUpload>(e =>
        {
            e.ToTable("catalog_uploads", t =>
            {
                t.HasCheckConstraint("ck_catalog_upload_status",
                    "status IN ('initiated','uploading','uploaded','validating','processing','ready','failed','cancelled','deleting')");
                t.HasCheckConstraint("ck_catalog_upload_active",
                    "NOT is_active OR (status = 'ready' AND computed_checksum_sha256 IS NOT NULL)");
                t.HasCheckConstraint("ck_catalog_upload_checksum",
                    "computed_checksum_sha256 IS NULL OR computed_checksum_sha256 = expected_checksum_sha256");
                t.HasCheckConstraint("ck_catalog_upload_key",
                    "source_bucket_key = 'tracks/' || track_id::text || '/generations/' || generation_id::text || '/source'");
                t.HasCheckConstraint("ck_catalog_upload_size", "size_bytes IS NULL OR size_bytes > 0");
                t.HasCheckConstraint("ck_catalog_upload_duration", "duration_ms IS NULL OR duration_ms > 0");
            });
            e.HasKey(x => x.GenerationId);
            e.Property(x => x.GenerationId).HasDefaultValueSql("gen_random_uuid()");
            e.HasAlternateKey(x => new { x.TrackId, x.GenerationId })
                .HasName("ux_catalog_upload_track_generation");
            e.HasIndex(x => x.TrackId).IsUnique().HasDatabaseName("ux_catalog_upload_active")
                .HasFilter("is_active");
            e.HasIndex(x => new { x.Status, x.LeaseExpiresAt }).HasDatabaseName("ix_catalog_upload_lease");
            e.HasIndex(x => new { x.TrackId, x.CreatedAt }).HasDatabaseName("ix_catalog_upload_track_created");
            e.HasOne(x => x.Track).WithMany(x => x.Uploads).HasForeignKey(x => x.TrackId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<TrackRendition>(e =>
        {
            e.ToTable("track_renditions", t =>
            {
                t.HasCheckConstraint("ck_tr_profile", "profile_code IN ('aac_128', 'aac_256', 'src')");
                t.HasCheckConstraint("ck_tr_status", "status IN ('pending', 'processing', 'ready', 'failed')");
                t.HasCheckConstraint("ck_tr_bitrate", "bitrate_kbps IS NULL OR bitrate_kbps > 0");
                t.HasCheckConstraint("ck_tr_size", "size_bytes IS NULL OR size_bytes > 0");
                t.HasCheckConstraint("ck_tr_duration", "duration_ms IS NULL OR duration_ms > 0");
                t.HasCheckConstraint("ck_tr_key_scope",
                    "bucket_key IS NULL OR bucket_key LIKE 'tracks/' || track_id::text || '/generations/' || generation_id::text || '/%'");
                t.HasCheckConstraint("ck_tr_ready",
                    "status <> 'ready' OR (bucket_key IS NOT NULL AND content_type IS NOT NULL AND size_bytes > 0 AND duration_ms > 0)");
            });
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.HasIndex(x => new { x.GenerationId, x.ProfileCode }).IsUnique()
                .HasDatabaseName("ux_track_renditions_profile");
            e.HasIndex(x => new { x.TrackId, x.GenerationId }).HasDatabaseName("ix_track_renditions_ready")
                .HasFilter("status = 'ready'");
            e.HasIndex(x => x.BucketKey).IsUnique().HasDatabaseName("ux_track_renditions_bucket")
                .HasFilter("bucket_key IS NOT NULL");
            e.HasOne(x => x.Upload).WithMany(x => x.Renditions)
                .HasForeignKey(x => new { x.TrackId, x.GenerationId })
                .HasPrincipalKey(x => new { x.TrackId, x.GenerationId })
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<ObjectDeletion>(e =>
        {
            e.ToTable("object_deletions", t =>
            {
                t.HasCheckConstraint("ck_od_status", "status IN ('pending','processing','done','failed')");
                t.HasCheckConstraint("ck_od_attempt", "attempt_count >= 0");
                t.HasCheckConstraint("ck_od_completed", "(status = 'done') = (completed_at IS NOT NULL)");
            });
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.HasIndex(x => x.BucketKey).IsUnique().HasDatabaseName("ux_object_deletions_pending")
                .HasFilter("status <> 'done'");
            e.HasIndex(x => new { x.Status, x.NextAttemptAt }).HasDatabaseName("ix_object_deletions_due");
            e.HasIndex(x => x.OwnerUserId).HasDatabaseName("ix_object_deletions_owner");
            e.HasOne(x => x.Owner).WithMany().HasForeignKey(x => x.OwnerUserId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<IdempotencyRecord>(e =>
        {
            e.ToTable("idempotency_records", t =>
            {
                t.HasCheckConstraint("ck_idempotency_response", "response_status BETWEEN 200 AND 599");
                t.HasCheckConstraint("ck_idempotency_expiry", "expires_at > created_at");
            });
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.Property(x => x.ResponseBody).HasColumnType("jsonb");
            e.HasIndex(x => new { x.UserId, x.Route, x.IdempotencyKey }).IsUnique()
                .HasDatabaseName("ux_idempotency_scope");
            e.HasIndex(x => x.ExpiresAt).HasDatabaseName("ix_idempotency_expiry");
            e.HasOne(x => x.User).WithMany().HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<PlaybackState>(e =>
        {
            e.ToTable("playback_states", t =>
            {
                t.HasCheckConstraint("ck_ps_pos", "position_ms >= 0");
                t.HasCheckConstraint("ck_ps_source", "source IS NULL OR source IN ('catalog', 'local', 'private')");
                t.HasCheckConstraint("ck_ps_quality",
                    "quality_code IS NULL OR quality_code IN ('auto','aac_128','aac_256','src')");
                t.HasCheckConstraint("ck_ps_revision", "revision >= 0");
                t.HasCheckConstraint("ck_ps_queue",
                    "jsonb_typeof(queue) = 'object' AND queue->>'schemaVersion' = '1' AND queue->>'repeat' IN ('off', 'one', 'all') AND queue ? 'currentItemId' AND jsonb_typeof(queue->'items') = 'array' AND jsonb_typeof(queue->'shuffle') = 'boolean' AND jsonb_array_length(queue->'items') <= 500 AND octet_length(queue::text) <= 262144");
                t.HasCheckConstraint("ck_ps_empty",
                    "track_id IS NOT NULL OR (position_ms = 0 AND is_playing = false AND source IS NULL AND quality_code IS NULL)");
            });
            e.HasKey(x => x.UserId);
            e.Property(x => x.Revision).HasDefaultValue(0L);
            e.Property(x => x.PositionMs).HasDefaultValue(0);
            e.Property(x => x.Queue).HasColumnType("jsonb")
                .HasDefaultValueSql("'{\"schemaVersion\":1,\"repeat\":\"off\",\"shuffle\":false,\"currentItemId\":null,\"items\":[]}'::jsonb");
            e.HasIndex(x => x.TrackId).HasDatabaseName("ix_playback_track")
                .HasFilter("track_id IS NOT NULL");
            e.HasOne(x => x.User).WithOne(x => x.PlaybackState).HasForeignKey<PlaybackState>(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Track).WithMany().HasForeignKey(x => x.TrackId)
                .OnDelete(DeleteBehavior.SetNull);
        });

        modelBuilder.Entity<UserTrackOverride>(e =>
        {
            e.ToTable("user_track_overrides", t =>
            {
                t.HasCheckConstraint("ck_uto_source", "source_preference IN ('auto', 'catalog', 'local', 'private')");
                t.HasCheckConstraint("ck_uto_duration", "duration_ms IS NULL OR duration_ms > 0");
                t.HasCheckConstraint("ck_uto_size", "size_bytes IS NULL OR size_bytes > 0");
            });
            e.HasKey(x => new { x.UserId, x.TrackId });
            e.Property(x => x.SourcePreference).HasDefaultValue("auto");
            e.HasIndex(x => x.TrackId).HasDatabaseName("ix_overrides_track");
            e.HasOne(x => x.User).WithMany(x => x.Overrides).HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Track).WithMany(x => x.Overrides).HasForeignKey(x => x.TrackId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<UserPrivateUpload>(e =>
        {
            e.ToTable("user_private_uploads", t =>
            {
                t.HasCheckConstraint("ck_private_upload_status",
                    "status IN ('initiated','uploading','uploaded','validating','processing','ready','failed','cancelled','deleting')");
                t.HasCheckConstraint("ck_private_upload_active",
                    "NOT is_active OR (status = 'ready' AND computed_checksum_sha256 IS NOT NULL)");
                t.HasCheckConstraint("ck_private_upload_checksum",
                    "computed_checksum_sha256 IS NULL OR computed_checksum_sha256 = expected_checksum_sha256");
                t.HasCheckConstraint("ck_private_upload_key",
                    "source_bucket_key = 'users/' || user_id::text || '/overrides/' || track_id::text || '/generations/' || generation_id::text || '/source'");
                t.HasCheckConstraint("ck_private_upload_size",
                    "size_bytes IS NULL OR size_bytes BETWEEN 1 AND 104857600");
                t.HasCheckConstraint("ck_private_upload_duration",
                    "duration_ms IS NULL OR duration_ms BETWEEN 1 AND 3600000");
            });
            e.HasKey(x => x.GenerationId);
            e.Property(x => x.GenerationId).HasDefaultValueSql("gen_random_uuid()");
            e.HasAlternateKey(x => new { x.UserId, x.TrackId, x.GenerationId })
                .HasName("ux_private_upload_owner_generation");
            e.HasIndex(x => new { x.UserId, x.TrackId }).IsUnique().HasDatabaseName("ux_private_upload_active")
                .HasFilter("is_active");
            e.HasIndex(x => new { x.Status, x.LeaseExpiresAt }).HasDatabaseName("ix_private_upload_lease");
            e.HasOne(x => x.Override).WithMany(x => x.Uploads)
                .HasForeignKey(x => new { x.UserId, x.TrackId })
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<UserPrivateRendition>(e =>
        {
            e.ToTable("user_private_renditions", t =>
            {
                t.HasCheckConstraint("ck_upr_profile", "profile_code IN ('aac_128', 'aac_256', 'src')");
                t.HasCheckConstraint("ck_upr_status", "status IN ('pending', 'processing', 'ready', 'failed')");
                t.HasCheckConstraint("ck_upr_bitrate", "bitrate_kbps IS NULL OR bitrate_kbps > 0");
                t.HasCheckConstraint("ck_upr_size", "size_bytes IS NULL OR size_bytes > 0");
                t.HasCheckConstraint("ck_upr_duration", "duration_ms IS NULL OR duration_ms > 0");
                t.HasCheckConstraint("ck_upr_key_scope",
                    "bucket_key IS NULL OR bucket_key LIKE 'users/' || user_id::text || '/overrides/' || track_id::text || '/generations/' || generation_id::text || '/%'");
                t.HasCheckConstraint("ck_upr_ready",
                    "status <> 'ready' OR (bucket_key IS NOT NULL AND content_type IS NOT NULL AND size_bytes > 0 AND duration_ms > 0)");
            });
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.HasIndex(x => new { x.GenerationId, x.ProfileCode }).IsUnique()
                .HasDatabaseName("ux_upr_profile");
            e.HasIndex(x => new { x.UserId, x.TrackId, x.GenerationId }).HasDatabaseName("ix_private_renditions_ready")
                .HasFilter("status = 'ready'");
            e.HasIndex(x => x.BucketKey).IsUnique().HasDatabaseName("ux_private_renditions_bucket")
                .HasFilter("bucket_key IS NOT NULL");
            e.HasOne(x => x.Upload).WithMany(x => x.Renditions)
                .HasForeignKey(x => new { x.UserId, x.TrackId, x.GenerationId })
                .HasPrincipalKey(x => new { x.UserId, x.TrackId, x.GenerationId })
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<UserTrackStat>(e =>
        {
            e.ToTable("user_track_stats", t =>
            {
                t.HasCheckConstraint("ck_uts_play_count", "play_count >= 1");
            });
            e.HasKey(x => new { x.UserId, x.TrackId });
            e.HasIndex(x => x.TrackId).HasDatabaseName("ix_user_track_stats_track");
            e.HasOne(x => x.User).WithMany().HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Track).WithMany().HasForeignKey(x => x.TrackId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        modelBuilder.Entity<UserPlayHistory>(e =>
        {
            e.ToTable("user_play_history");
            e.HasKey(x => x.Id);
            e.Property(x => x.Id).HasDefaultValueSql("gen_random_uuid()");
            e.HasIndex(x => x.TrackId).HasDatabaseName("ix_user_play_history_track");
            e.HasIndex(x => new { x.UserId, x.PlayedAt, x.Id }).HasDatabaseName("ix_user_play_history_user");
            e.HasOne(x => x.User).WithMany().HasForeignKey(x => x.UserId)
                .OnDelete(DeleteBehavior.Cascade);
            e.HasOne(x => x.Track).WithMany().HasForeignKey(x => x.TrackId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
