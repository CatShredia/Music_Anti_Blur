using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MusicAntiBlur.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class Storage : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
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
                name: "ix_idempotency_expiry",
                table: "idempotency_records",
                column: "expires_at");

            migrationBuilder.CreateIndex(
                name: "ux_idempotency_scope",
                table: "idempotency_records",
                columns: new[] { "user_id", "route", "idempotency_key" },
                unique: true);

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
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "idempotency_records");

            migrationBuilder.DropTable(
                name: "object_deletions");

            migrationBuilder.DropTable(
                name: "track_renditions");

            migrationBuilder.DropTable(
                name: "catalog_uploads");
        }
    }
}
