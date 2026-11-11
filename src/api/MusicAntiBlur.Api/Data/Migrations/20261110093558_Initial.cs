using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace MusicAntiBlur.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class Initial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterDatabase()
                .Annotation("Npgsql:PostgresExtension:pg_trgm", ",,")
                .Annotation("Npgsql:PostgresExtension:pgcrypto", ",,");

            migrationBuilder.CreateTable(
                name: "artists",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    name = table.Column<string>(type: "text", nullable: false),
                    sort_name = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_artists", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "data_protection_keys",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    friendly_name = table.Column<string>(type: "text", nullable: true),
                    xml = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_data_protection_keys", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "genres",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    name = table.Column<string>(type: "text", nullable: false),
                    slug = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_genres", x => x.id);
                    table.CheckConstraint("ck_genres_name", "char_length(btrim(name)) BETWEEN 1 AND 60");
                });

            migrationBuilder.CreateTable(
                name: "users",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    login = table.Column<string>(type: "text", nullable: true),
                    email = table.Column<string>(type: "text", nullable: true),
                    email_verified_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    password_hash = table.Column<string>(type: "text", nullable: false),
                    role = table.Column<string>(type: "text", nullable: false, defaultValue: "user"),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_users", x => x.id);
                    table.CheckConstraint("ck_users_email_length", "email IS NULL OR (char_length(email) BETWEEN 3 AND 254)");
                    table.CheckConstraint("ck_users_email_normalized", "email IS NULL OR email = lower(btrim(email))");
                    table.CheckConstraint("ck_users_identifier", "login IS NOT NULL OR email IS NOT NULL");
                    table.CheckConstraint("ck_users_login_format", "login IS NULL OR login ~ '^[a-zA-Z0-9_.-]{3,32}$'");
                    table.CheckConstraint("ck_users_password_hash", "char_length(password_hash) > 0");
                    table.CheckConstraint("ck_users_role", "role IN ('user', 'admin')");
                    table.CheckConstraint("ck_users_verified_email", "email_verified_at IS NULL OR email IS NOT NULL");
                });

            migrationBuilder.CreateTable(
                name: "albums",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    artist_id = table.Column<Guid>(type: "uuid", nullable: false),
                    title = table.Column<string>(type: "text", nullable: false),
                    year = table.Column<int>(type: "integer", nullable: true),
                    cover_object_key = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_albums", x => x.id);
                    table.CheckConstraint("ck_albums_year", "year IS NULL OR year BETWEEN 1000 AND 9999");
                    table.ForeignKey(
                        name: "fk_albums_artists_artist_id",
                        column: x => x.artist_id,
                        principalTable: "artists",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "email_verification_tokens",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    pending_email = table.Column<string>(type: "text", nullable: false),
                    purpose = table.Column<string>(type: "text", nullable: false),
                    token_hash = table.Column<string>(type: "text", nullable: false),
                    expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    used_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    invalidated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_email_verification_tokens", x => x.id);
                    table.CheckConstraint("ck_evt_email", "pending_email = lower(btrim(pending_email))");
                    table.CheckConstraint("ck_evt_expiry", "expires_at > created_at");
                    table.CheckConstraint("ck_evt_invalidated", "invalidated_at IS NULL OR invalidated_at >= created_at");
                    table.CheckConstraint("ck_evt_purpose", "purpose IN ('register', 'bind')");
                    table.CheckConstraint("ck_evt_terminal", "used_at IS NULL OR invalidated_at IS NULL");
                    table.CheckConstraint("ck_evt_used", "used_at IS NULL OR used_at >= created_at");
                    table.ForeignKey(
                        name: "fk_email_verification_tokens_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "idempotency_records",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    route = table.Column<string>(type: "text", nullable: false),
                    idempotency_key = table.Column<Guid>(type: "uuid", nullable: false),
                    request_hash = table.Column<string>(type: "text", nullable: false),
                    response_status = table.Column<int>(type: "integer", nullable: false),
                    response_body = table.Column<string>(type: "jsonb", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_idempotency_records", x => x.id);
                    table.CheckConstraint("ck_idempotency_expiry", "expires_at > created_at");
                    table.CheckConstraint("ck_idempotency_response", "response_status BETWEEN 200 AND 599");
                    table.ForeignKey(
                        name: "fk_idempotency_records_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "login_events",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    device_id = table.Column<Guid>(type: "uuid", nullable: true),
                    at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ip = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    user_agent = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: true),
                    result = table.Column<string>(type: "text", nullable: false),
                    method = table.Column<string>(type: "text", nullable: false),
                    not_me_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_login_events", x => x.id);
                    table.CheckConstraint("ck_login_events_method", "method IN ('password', 'totp', 'email', 'recovery', 'refresh')");
                    table.CheckConstraint("ck_login_events_result", "result IN ('success', 'bad_password', '2fa_required', '2fa_failed', 'refresh_reuse')");
                    table.ForeignKey(
                        name: "fk_login_events_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "object_deletions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    owner_user_id = table.Column<Guid>(type: "uuid", nullable: true),
                    bucket_key = table.Column<string>(type: "text", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    attempt_count = table.Column<int>(type: "integer", nullable: false),
                    next_attempt_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    lease_expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    last_error = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    completed_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_object_deletions", x => x.id);
                    table.CheckConstraint("ck_od_attempt", "attempt_count >= 0");
                    table.CheckConstraint("ck_od_completed", "(status = 'done') = (completed_at IS NOT NULL)");
                    table.CheckConstraint("ck_od_status", "status IN ('pending','processing','done','failed')");
                    table.ForeignKey(
                        name: "fk_object_deletions_users_owner_user_id",
                        column: x => x.owner_user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateTable(
                name: "password_reset_tokens",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    token_hash = table.Column<string>(type: "text", nullable: false),
                    expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    used_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    invalidated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_password_reset_tokens", x => x.id);
                    table.CheckConstraint("ck_reset_expiry", "expires_at > created_at");
                    table.CheckConstraint("ck_reset_invalidated", "invalidated_at IS NULL OR invalidated_at >= created_at");
                    table.CheckConstraint("ck_reset_terminal", "used_at IS NULL OR invalidated_at IS NULL");
                    table.CheckConstraint("ck_reset_used", "used_at IS NULL OR used_at >= created_at");
                    table.ForeignKey(
                        name: "fk_password_reset_tokens_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "playlists",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    title = table.Column<string>(type: "text", nullable: false),
                    kind = table.Column<string>(type: "text", nullable: false),
                    description = table.Column<string>(type: "text", nullable: true),
                    is_public = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_playlists", x => x.id);
                    table.CheckConstraint("ck_playlists_description", "description IS NULL OR char_length(description) <= 500");
                    table.CheckConstraint("ck_playlists_kind", "kind IN ('liked', 'user')");
                    table.CheckConstraint("ck_playlists_liked_private", "kind <> 'liked' OR NOT is_public");
                    table.CheckConstraint("ck_playlists_liked_title", "kind <> 'liked' OR title = 'Мне нравится'");
                    table.CheckConstraint("ck_playlists_title", "char_length(btrim(title)) BETWEEN 1 AND 200");
                    table.ForeignKey(
                        name: "fk_playlists_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "refresh_tokens",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    token_hash = table.Column<string>(type: "text", nullable: false),
                    device_id = table.Column<Guid>(type: "uuid", nullable: false),
                    family_id = table.Column<Guid>(type: "uuid", nullable: false),
                    parent_token_id = table.Column<Guid>(type: "uuid", nullable: true),
                    expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    revoked_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    revoke_reason = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_refresh_tokens", x => x.id);
                    table.CheckConstraint("ck_refresh_expiry", "expires_at > created_at");
                    table.CheckConstraint("ck_refresh_revoked", "revoked_at IS NULL OR revoked_at >= created_at");
                    table.ForeignKey(
                        name: "fk_refresh_tokens_refresh_tokens_parent_token_id",
                        column: x => x.parent_token_id,
                        principalTable: "refresh_tokens",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_refresh_tokens_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "search_history",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    query = table.Column<string>(type: "text", nullable: false),
                    normalized = table.Column<string>(type: "text", nullable: false),
                    searched_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_search_history", x => x.id);
                    table.CheckConstraint("ck_search_history_query", "char_length(query) BETWEEN 2 AND 100");
                    table.ForeignKey(
                        name: "fk_search_history_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_quotas",
                columns: table => new
                {
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    max_bytes = table.Column<long>(type: "bigint", nullable: true),
                    max_files = table.Column<int>(type: "integer", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_quotas", x => x.user_id);
                    table.CheckConstraint("ck_user_quotas_bytes", "max_bytes IS NULL OR max_bytes >= 0");
                    table.CheckConstraint("ck_user_quotas_files", "max_files IS NULL OR max_files >= 0");
                    table.ForeignKey(
                        name: "fk_user_quotas_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_recovery_codes",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    code_hash = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    used_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_recovery_codes", x => x.id);
                    table.ForeignKey(
                        name: "fk_user_recovery_codes_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_settings",
                columns: table => new
                {
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    preferred_quality = table.Column<string>(type: "text", nullable: false, defaultValue: "auto"),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_settings", x => x.user_id);
                    table.CheckConstraint("ck_settings_quality", "preferred_quality IN ('auto', 'aac_128', 'aac_256', 'src')");
                    table.ForeignKey(
                        name: "fk_user_settings_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_two_factor",
                columns: table => new
                {
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    totp_secret_protected = table.Column<string>(type: "text", nullable: true),
                    totp_enabled_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    email_otp_enabled = table.Column<bool>(type: "boolean", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_two_factor", x => x.user_id);
                    table.CheckConstraint("ck_2fa_totp", "(totp_secret_protected IS NULL) = (totp_enabled_at IS NULL)");
                    table.ForeignKey(
                        name: "fk_user_two_factor_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "album_genres",
                columns: table => new
                {
                    album_id = table.Column<Guid>(type: "uuid", nullable: false),
                    genre_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_album_genres", x => new { x.album_id, x.genre_id });
                    table.ForeignKey(
                        name: "fk_album_genres_albums_album_id",
                        column: x => x.album_id,
                        principalTable: "albums",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_album_genres_genres_genre_id",
                        column: x => x.genre_id,
                        principalTable: "genres",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "saved_albums",
                columns: table => new
                {
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    album_id = table.Column<Guid>(type: "uuid", nullable: false),
                    added_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_saved_albums", x => new { x.user_id, x.album_id });
                    table.ForeignKey(
                        name: "fk_saved_albums_albums_album_id",
                        column: x => x.album_id,
                        principalTable: "albums",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_saved_albums_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "tracks",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    album_id = table.Column<Guid>(type: "uuid", nullable: false),
                    artist_id = table.Column<Guid>(type: "uuid", nullable: false),
                    title = table.Column<string>(type: "text", nullable: false),
                    track_number = table.Column<int>(type: "integer", nullable: false),
                    duration_ms = table.Column<int>(type: "integer", nullable: true),
                    isrc = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    deleted_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_tracks", x => x.id);
                    table.CheckConstraint("ck_tracks_duration", "duration_ms IS NULL OR duration_ms > 0");
                    table.CheckConstraint("ck_tracks_number", "track_number >= 1");
                    table.ForeignKey(
                        name: "fk_tracks_albums_album_id",
                        column: x => x.album_id,
                        principalTable: "albums",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_tracks_artists_artist_id",
                        column: x => x.artist_id,
                        principalTable: "artists",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "saved_playlists",
                columns: table => new
                {
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    playlist_id = table.Column<Guid>(type: "uuid", nullable: false),
                    added_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_saved_playlists", x => new { x.user_id, x.playlist_id });
                    table.ForeignKey(
                        name: "fk_saved_playlists_playlists_playlist_id",
                        column: x => x.playlist_id,
                        principalTable: "playlists",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_saved_playlists_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "catalog_uploads",
                columns: table => new
                {
                    generation_id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false),
                    multipart_upload_id = table.Column<string>(type: "text", nullable: true),
                    source_bucket_key = table.Column<string>(type: "text", nullable: false),
                    expected_checksum_sha256 = table.Column<string>(type: "text", nullable: false),
                    computed_checksum_sha256 = table.Column<string>(type: "text", nullable: true),
                    size_bytes = table.Column<long>(type: "bigint", nullable: true),
                    duration_ms = table.Column<int>(type: "integer", nullable: true),
                    lease_expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_catalog_uploads", x => x.generation_id);
                    table.UniqueConstraint("ux_catalog_upload_track_generation", x => new { x.track_id, x.generation_id });
                    table.CheckConstraint("ck_catalog_upload_active", "NOT is_active OR (status = 'ready' AND computed_checksum_sha256 IS NOT NULL)");
                    table.CheckConstraint("ck_catalog_upload_checksum", "computed_checksum_sha256 IS NULL OR computed_checksum_sha256 = expected_checksum_sha256");
                    table.CheckConstraint("ck_catalog_upload_duration", "duration_ms IS NULL OR duration_ms > 0");
                    table.CheckConstraint("ck_catalog_upload_key", "source_bucket_key = 'tracks/' || track_id::text || '/generations/' || generation_id::text || '/source'");
                    table.CheckConstraint("ck_catalog_upload_size", "size_bytes IS NULL OR size_bytes > 0");
                    table.CheckConstraint("ck_catalog_upload_status", "status IN ('initiated','uploading','uploaded','validating','processing','ready','failed','cancelled','deleting')");
                    table.ForeignKey(
                        name: "fk_catalog_uploads_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "liked_tracks",
                columns: table => new
                {
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    liked_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_liked_tracks", x => new { x.user_id, x.track_id });
                    table.ForeignKey(
                        name: "fk_liked_tracks_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_liked_tracks_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "playback_states",
                columns: table => new
                {
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: true),
                    position_ms = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    is_playing = table.Column<bool>(type: "boolean", nullable: false),
                    quality_code = table.Column<string>(type: "text", nullable: true),
                    source = table.Column<string>(type: "text", nullable: true),
                    device_id = table.Column<Guid>(type: "uuid", nullable: true),
                    writer_session_id = table.Column<Guid>(type: "uuid", nullable: true),
                    revision = table.Column<long>(type: "bigint", nullable: false, defaultValue: 0L),
                    queue = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{\"schemaVersion\":1,\"repeat\":\"off\",\"shuffle\":false,\"currentItemId\":null,\"items\":[]}'::jsonb"),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_playback_states", x => x.user_id);
                    table.CheckConstraint("ck_ps_empty", "track_id IS NOT NULL OR (position_ms = 0 AND is_playing = false AND source IS NULL AND quality_code IS NULL)");
                    table.CheckConstraint("ck_ps_pos", "position_ms >= 0");
                    table.CheckConstraint("ck_ps_quality", "quality_code IS NULL OR quality_code IN ('auto','aac_128','aac_256','src')");
                    table.CheckConstraint("ck_ps_queue", "jsonb_typeof(queue) = 'object' AND queue->>'schemaVersion' = '1' AND queue->>'repeat' IN ('off', 'one', 'all') AND queue ? 'currentItemId' AND jsonb_typeof(queue->'items') = 'array' AND jsonb_typeof(queue->'shuffle') = 'boolean' AND jsonb_array_length(queue->'items') <= 500 AND octet_length(queue::text) <= 262144");
                    table.CheckConstraint("ck_ps_revision", "revision >= 0");
                    table.CheckConstraint("ck_ps_source", "source IS NULL OR source IN ('catalog', 'local', 'private')");
                    table.ForeignKey(
                        name: "fk_playback_states_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "fk_playback_states_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "playlist_tracks",
                columns: table => new
                {
                    playlist_id = table.Column<Guid>(type: "uuid", nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    position = table.Column<int>(type: "integer", nullable: false),
                    added_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_playlist_tracks", x => new { x.playlist_id, x.track_id });
                    table.CheckConstraint("ck_playlist_tracks_position", "position >= 0");
                    table.ForeignKey(
                        name: "fk_playlist_tracks_playlists_playlist_id",
                        column: x => x.playlist_id,
                        principalTable: "playlists",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_playlist_tracks_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "track_genres",
                columns: table => new
                {
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    genre_id = table.Column<Guid>(type: "uuid", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_track_genres", x => new { x.track_id, x.genre_id });
                    table.ForeignKey(
                        name: "fk_track_genres_genres_genre_id",
                        column: x => x.genre_id,
                        principalTable: "genres",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_track_genres_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_play_history",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    played_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_play_history", x => x.id);
                    table.ForeignKey(
                        name: "fk_user_play_history_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_user_play_history_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_track_overrides",
                columns: table => new
                {
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    source_preference = table.Column<string>(type: "text", nullable: false, defaultValue: "auto"),
                    display_name = table.Column<string>(type: "text", nullable: true),
                    duration_ms = table.Column<int>(type: "integer", nullable: true),
                    size_bytes = table.Column<long>(type: "bigint", nullable: true),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_track_overrides", x => new { x.user_id, x.track_id });
                    table.CheckConstraint("ck_uto_duration", "duration_ms IS NULL OR duration_ms > 0");
                    table.CheckConstraint("ck_uto_size", "size_bytes IS NULL OR size_bytes > 0");
                    table.CheckConstraint("ck_uto_source", "source_preference IN ('auto', 'catalog', 'local', 'private')");
                    table.ForeignKey(
                        name: "fk_user_track_overrides_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_user_track_overrides_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_track_stats",
                columns: table => new
                {
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    play_count = table.Column<int>(type: "integer", nullable: false),
                    last_played_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_track_stats", x => new { x.user_id, x.track_id });
                    table.CheckConstraint("ck_uts_play_count", "play_count >= 1");
                    table.ForeignKey(
                        name: "fk_user_track_stats_tracks_track_id",
                        column: x => x.track_id,
                        principalTable: "tracks",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "fk_user_track_stats_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "track_renditions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    generation_id = table.Column<Guid>(type: "uuid", nullable: false),
                    profile_code = table.Column<string>(type: "text", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    bucket_key = table.Column<string>(type: "text", nullable: true),
                    content_type = table.Column<string>(type: "text", nullable: true),
                    bitrate_kbps = table.Column<int>(type: "integer", nullable: true),
                    size_bytes = table.Column<long>(type: "bigint", nullable: true),
                    duration_ms = table.Column<int>(type: "integer", nullable: true),
                    error_message = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_track_renditions", x => x.id);
                    table.CheckConstraint("ck_tr_bitrate", "bitrate_kbps IS NULL OR bitrate_kbps > 0");
                    table.CheckConstraint("ck_tr_duration", "duration_ms IS NULL OR duration_ms > 0");
                    table.CheckConstraint("ck_tr_key_scope", "bucket_key IS NULL OR bucket_key LIKE 'tracks/' || track_id::text || '/generations/' || generation_id::text || '/%'");
                    table.CheckConstraint("ck_tr_profile", "profile_code IN ('aac_128', 'aac_256', 'src')");
                    table.CheckConstraint("ck_tr_ready", "status <> 'ready' OR (bucket_key IS NOT NULL AND content_type IS NOT NULL AND size_bytes > 0 AND duration_ms > 0)");
                    table.CheckConstraint("ck_tr_size", "size_bytes IS NULL OR size_bytes > 0");
                    table.CheckConstraint("ck_tr_status", "status IN ('pending', 'processing', 'ready', 'failed')");
                    table.ForeignKey(
                        name: "fk_track_renditions_catalog_uploads_track_id_generation_id",
                        columns: x => new { x.track_id, x.generation_id },
                        principalTable: "catalog_uploads",
                        principalColumns: new[] { "track_id", "generation_id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_private_uploads",
                columns: table => new
                {
                    generation_id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false),
                    multipart_upload_id = table.Column<string>(type: "text", nullable: true),
                    source_bucket_key = table.Column<string>(type: "text", nullable: false),
                    expected_checksum_sha256 = table.Column<string>(type: "text", nullable: false),
                    computed_checksum_sha256 = table.Column<string>(type: "text", nullable: true),
                    size_bytes = table.Column<long>(type: "bigint", nullable: true),
                    duration_ms = table.Column<int>(type: "integer", nullable: true),
                    lease_expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_private_uploads", x => x.generation_id);
                    table.UniqueConstraint("ux_private_upload_owner_generation", x => new { x.user_id, x.track_id, x.generation_id });
                    table.CheckConstraint("ck_private_upload_active", "NOT is_active OR (status = 'ready' AND computed_checksum_sha256 IS NOT NULL)");
                    table.CheckConstraint("ck_private_upload_checksum", "computed_checksum_sha256 IS NULL OR computed_checksum_sha256 = expected_checksum_sha256");
                    table.CheckConstraint("ck_private_upload_duration", "duration_ms IS NULL OR duration_ms BETWEEN 1 AND 3600000");
                    table.CheckConstraint("ck_private_upload_key", "source_bucket_key = 'users/' || user_id::text || '/overrides/' || track_id::text || '/generations/' || generation_id::text || '/source'");
                    table.CheckConstraint("ck_private_upload_size", "size_bytes IS NULL OR size_bytes BETWEEN 1 AND 104857600");
                    table.CheckConstraint("ck_private_upload_status", "status IN ('initiated','uploading','uploaded','validating','processing','ready','failed','cancelled','deleting')");
                    table.ForeignKey(
                        name: "fk_user_private_uploads_user_track_overrides_user_id_track_id",
                        columns: x => new { x.user_id, x.track_id },
                        principalTable: "user_track_overrides",
                        principalColumns: new[] { "user_id", "track_id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "user_private_renditions",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    track_id = table.Column<Guid>(type: "uuid", nullable: false),
                    generation_id = table.Column<Guid>(type: "uuid", nullable: false),
                    profile_code = table.Column<string>(type: "text", nullable: false),
                    status = table.Column<string>(type: "text", nullable: false),
                    bucket_key = table.Column<string>(type: "text", nullable: true),
                    content_type = table.Column<string>(type: "text", nullable: true),
                    bitrate_kbps = table.Column<int>(type: "integer", nullable: true),
                    size_bytes = table.Column<long>(type: "bigint", nullable: true),
                    duration_ms = table.Column<int>(type: "integer", nullable: true),
                    error_message = table.Column<string>(type: "text", nullable: true),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_user_private_renditions", x => x.id);
                    table.CheckConstraint("ck_upr_bitrate", "bitrate_kbps IS NULL OR bitrate_kbps > 0");
                    table.CheckConstraint("ck_upr_duration", "duration_ms IS NULL OR duration_ms > 0");
                    table.CheckConstraint("ck_upr_key_scope", "bucket_key IS NULL OR bucket_key LIKE 'users/' || user_id::text || '/overrides/' || track_id::text || '/generations/' || generation_id::text || '/%'");
                    table.CheckConstraint("ck_upr_profile", "profile_code IN ('aac_128', 'aac_256', 'src')");
                    table.CheckConstraint("ck_upr_ready", "status <> 'ready' OR (bucket_key IS NOT NULL AND content_type IS NOT NULL AND size_bytes > 0 AND duration_ms > 0)");
                    table.CheckConstraint("ck_upr_size", "size_bytes IS NULL OR size_bytes > 0");
                    table.CheckConstraint("ck_upr_status", "status IN ('pending', 'processing', 'ready', 'failed')");
                    table.ForeignKey(
                        name: "fk_user_private_renditions_user_private_uploads_user_id_track_",
                        columns: x => new { x.user_id, x.track_id, x.generation_id },
                        principalTable: "user_private_uploads",
                        principalColumns: new[] { "user_id", "track_id", "generation_id" },
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_album_genres_genre",
                table: "album_genres",
                column: "genre_id");

            migrationBuilder.CreateIndex(
                name: "gin_albums_title",
                table: "albums",
                column: "title")
                .Annotation("Npgsql:IndexMethod", "gin")
                .Annotation("Npgsql:IndexOperators", new[] { "gin_trgm_ops" });

            migrationBuilder.CreateIndex(
                name: "ix_albums_artist",
                table: "albums",
                column: "artist_id");

            migrationBuilder.CreateIndex(
                name: "ix_albums_deleted_at",
                table: "albums",
                column: "deleted_at",
                filter: "deleted_at IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "gin_artists_name",
                table: "artists",
                column: "name")
                .Annotation("Npgsql:IndexMethod", "gin")
                .Annotation("Npgsql:IndexOperators", new[] { "gin_trgm_ops" });

            migrationBuilder.CreateIndex(
                name: "ix_artists_deleted_at",
                table: "artists",
                column: "deleted_at",
                filter: "deleted_at IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "ix_artists_sort_name",
                table: "artists",
                column: "sort_name");

            migrationBuilder.CreateIndex(
                name: "ix_catalog_upload_lease",
                table: "catalog_uploads",
                columns: new[] { "status", "lease_expires_at" });

            migrationBuilder.CreateIndex(
                name: "ix_catalog_upload_track_created",
                table: "catalog_uploads",
                columns: new[] { "track_id", "created_at" });

            migrationBuilder.CreateIndex(
                name: "ux_catalog_upload_active",
                table: "catalog_uploads",
                column: "track_id",
                unique: true,
                filter: "is_active");

            migrationBuilder.CreateIndex(
                name: "ix_email_verification_expiry",
                table: "email_verification_tokens",
                column: "expires_at");

            migrationBuilder.CreateIndex(
                name: "ix_email_verification_user",
                table: "email_verification_tokens",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ux_email_verification_hash",
                table: "email_verification_tokens",
                column: "token_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ux_evt_pending_email_active",
                table: "email_verification_tokens",
                column: "pending_email",
                unique: true,
                filter: "used_at IS NULL AND invalidated_at IS NULL AND purpose = 'bind'");

            migrationBuilder.CreateIndex(
                name: "gin_genres_name",
                table: "genres",
                column: "name")
                .Annotation("Npgsql:IndexMethod", "gin")
                .Annotation("Npgsql:IndexOperators", new[] { "gin_trgm_ops" });

            migrationBuilder.CreateIndex(
                name: "ux_genres_slug",
                table: "genres",
                column: "slug",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_idempotency_expiry",
                table: "idempotency_records",
                column: "expires_at");

            migrationBuilder.CreateIndex(
                name: "ux_idempotency_scope",
                table: "idempotency_records",
                columns: new[] { "user_id", "route", "idempotency_key" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_liked_tracks_track",
                table: "liked_tracks",
                column: "track_id");

            migrationBuilder.CreateIndex(
                name: "ix_liked_tracks_user_liked_at",
                table: "liked_tracks",
                columns: new[] { "user_id", "liked_at" });

            migrationBuilder.CreateIndex(
                name: "ix_login_events_at",
                table: "login_events",
                column: "at");

            migrationBuilder.CreateIndex(
                name: "ix_login_events_user_at",
                table: "login_events",
                columns: new[] { "user_id", "at", "id" });

            migrationBuilder.CreateIndex(
                name: "ix_object_deletions_due",
                table: "object_deletions",
                columns: new[] { "status", "next_attempt_at" });

            migrationBuilder.CreateIndex(
                name: "ix_object_deletions_owner",
                table: "object_deletions",
                column: "owner_user_id");

            migrationBuilder.CreateIndex(
                name: "ux_object_deletions_pending",
                table: "object_deletions",
                column: "bucket_key",
                unique: true,
                filter: "status <> 'done'");

            migrationBuilder.CreateIndex(
                name: "ix_password_reset_expiry",
                table: "password_reset_tokens",
                column: "expires_at");

            migrationBuilder.CreateIndex(
                name: "ix_password_reset_user",
                table: "password_reset_tokens",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ux_password_reset_hash",
                table: "password_reset_tokens",
                column: "token_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_playback_track",
                table: "playback_states",
                column: "track_id",
                filter: "track_id IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "ix_playlist_tracks_track",
                table: "playlist_tracks",
                column: "track_id");

            migrationBuilder.CreateIndex(
                name: "ux_playlist_tracks_position",
                table: "playlist_tracks",
                columns: new[] { "playlist_id", "position" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ux_playlists_user_liked",
                table: "playlists",
                column: "user_id",
                unique: true,
                filter: "kind = 'liked'");

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_device",
                table: "refresh_tokens",
                columns: new[] { "user_id", "device_id" });

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_expiry",
                table: "refresh_tokens",
                column: "expires_at");

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_family",
                table: "refresh_tokens",
                column: "family_id");

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_parent_token_id",
                table: "refresh_tokens",
                column: "parent_token_id");

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_user",
                table: "refresh_tokens",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ux_refresh_tokens_hash",
                table: "refresh_tokens",
                column: "token_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_saved_albums_album",
                table: "saved_albums",
                column: "album_id");

            migrationBuilder.CreateIndex(
                name: "ix_saved_albums_user_added",
                table: "saved_albums",
                columns: new[] { "user_id", "added_at" });

            migrationBuilder.CreateIndex(
                name: "ix_saved_playlists_playlist",
                table: "saved_playlists",
                column: "playlist_id");

            migrationBuilder.CreateIndex(
                name: "ix_saved_playlists_user_added",
                table: "saved_playlists",
                columns: new[] { "user_id", "added_at" });

            migrationBuilder.CreateIndex(
                name: "ix_search_history_user_time",
                table: "search_history",
                columns: new[] { "user_id", "searched_at" });

            migrationBuilder.CreateIndex(
                name: "ux_search_history_user_query",
                table: "search_history",
                columns: new[] { "user_id", "normalized" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_track_genres_genre",
                table: "track_genres",
                column: "genre_id");

            migrationBuilder.CreateIndex(
                name: "ix_track_renditions_ready",
                table: "track_renditions",
                columns: new[] { "track_id", "generation_id" },
                filter: "status = 'ready'");

            migrationBuilder.CreateIndex(
                name: "ux_track_renditions_bucket",
                table: "track_renditions",
                column: "bucket_key",
                unique: true,
                filter: "bucket_key IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "ux_track_renditions_profile",
                table: "track_renditions",
                columns: new[] { "generation_id", "profile_code" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "gin_tracks_title",
                table: "tracks",
                column: "title")
                .Annotation("Npgsql:IndexMethod", "gin")
                .Annotation("Npgsql:IndexOperators", new[] { "gin_trgm_ops" });

            migrationBuilder.CreateIndex(
                name: "ix_tracks_artist",
                table: "tracks",
                column: "artist_id");

            migrationBuilder.CreateIndex(
                name: "ix_tracks_deleted_at",
                table: "tracks",
                column: "deleted_at",
                filter: "deleted_at IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "ux_tracks_album_number",
                table: "tracks",
                columns: new[] { "album_id", "track_number" },
                unique: true,
                filter: "deleted_at IS NULL");

            migrationBuilder.CreateIndex(
                name: "ux_tracks_isrc",
                table: "tracks",
                column: "isrc",
                unique: true,
                filter: "isrc IS NOT NULL AND deleted_at IS NULL");

            migrationBuilder.CreateIndex(
                name: "ix_user_play_history_track",
                table: "user_play_history",
                column: "track_id");

            migrationBuilder.CreateIndex(
                name: "ix_user_play_history_user",
                table: "user_play_history",
                columns: new[] { "user_id", "played_at", "id" });

            migrationBuilder.CreateIndex(
                name: "ix_private_renditions_ready",
                table: "user_private_renditions",
                columns: new[] { "user_id", "track_id", "generation_id" },
                filter: "status = 'ready'");

            migrationBuilder.CreateIndex(
                name: "ux_private_renditions_bucket",
                table: "user_private_renditions",
                column: "bucket_key",
                unique: true,
                filter: "bucket_key IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "ux_upr_profile",
                table: "user_private_renditions",
                columns: new[] { "generation_id", "profile_code" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_private_upload_lease",
                table: "user_private_uploads",
                columns: new[] { "status", "lease_expires_at" });

            migrationBuilder.CreateIndex(
                name: "ux_private_upload_active",
                table: "user_private_uploads",
                columns: new[] { "user_id", "track_id" },
                unique: true,
                filter: "is_active");

            migrationBuilder.CreateIndex(
                name: "ux_recovery_codes_user_hash",
                table: "user_recovery_codes",
                columns: new[] { "user_id", "code_hash" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_overrides_track",
                table: "user_track_overrides",
                column: "track_id");

            migrationBuilder.CreateIndex(
                name: "ix_user_track_stats_track",
                table: "user_track_stats",
                column: "track_id");

            // Регистронезависимая уникальность: индексы по lower(...) EF не умеет, поэтому SQL.
            migrationBuilder.Sql(
                """CREATE UNIQUE INDEX ux_users_email_lower ON users (lower(email)) WHERE email IS NOT NULL;""");
            migrationBuilder.Sql(
                """CREATE UNIQUE INDEX ux_users_login_lower ON users (lower(login)) WHERE login IS NOT NULL;""");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "album_genres");

            migrationBuilder.DropTable(
                name: "data_protection_keys");

            migrationBuilder.DropTable(
                name: "email_verification_tokens");

            migrationBuilder.DropTable(
                name: "idempotency_records");

            migrationBuilder.DropTable(
                name: "liked_tracks");

            migrationBuilder.DropTable(
                name: "login_events");

            migrationBuilder.DropTable(
                name: "object_deletions");

            migrationBuilder.DropTable(
                name: "password_reset_tokens");

            migrationBuilder.DropTable(
                name: "playback_states");

            migrationBuilder.DropTable(
                name: "playlist_tracks");

            migrationBuilder.DropTable(
                name: "refresh_tokens");

            migrationBuilder.DropTable(
                name: "saved_albums");

            migrationBuilder.DropTable(
                name: "saved_playlists");

            migrationBuilder.DropTable(
                name: "search_history");

            migrationBuilder.DropTable(
                name: "track_genres");

            migrationBuilder.DropTable(
                name: "track_renditions");

            migrationBuilder.DropTable(
                name: "user_play_history");

            migrationBuilder.DropTable(
                name: "user_private_renditions");

            migrationBuilder.DropTable(
                name: "user_quotas");

            migrationBuilder.DropTable(
                name: "user_recovery_codes");

            migrationBuilder.DropTable(
                name: "user_settings");

            migrationBuilder.DropTable(
                name: "user_track_stats");

            migrationBuilder.DropTable(
                name: "user_two_factor");

            migrationBuilder.DropTable(
                name: "playlists");

            migrationBuilder.DropTable(
                name: "genres");

            migrationBuilder.DropTable(
                name: "catalog_uploads");

            migrationBuilder.DropTable(
                name: "user_private_uploads");

            migrationBuilder.DropTable(
                name: "user_track_overrides");

            migrationBuilder.DropTable(
                name: "tracks");

            migrationBuilder.DropTable(
                name: "users");

            migrationBuilder.DropTable(
                name: "albums");

            migrationBuilder.DropTable(
                name: "artists");
        }
    }
}
