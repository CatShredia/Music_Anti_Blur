using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MusicAntiBlur.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class Override : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
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
                name: "ix_overrides_track",
                table: "user_track_overrides",
                column: "track_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "user_private_renditions");

            migrationBuilder.DropTable(
                name: "user_private_uploads");

            migrationBuilder.DropTable(
                name: "user_track_overrides");
        }
    }
}
