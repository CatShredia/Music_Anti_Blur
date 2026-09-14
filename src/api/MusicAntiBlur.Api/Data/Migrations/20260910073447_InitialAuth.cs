using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MusicAntiBlur.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class InitialAuth : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterDatabase()
                .Annotation("Npgsql:PostgresExtension:pg_trgm", ",,")
                .Annotation("Npgsql:PostgresExtension:pgcrypto", ",,");

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
                    table.CheckConstraint("ck_users_email_normalized", "email IS NULL OR email = lower(btrim(email))");
                    table.CheckConstraint("ck_users_identifier", "login IS NOT NULL OR email IS NOT NULL");
                    table.CheckConstraint("ck_users_login_format", "login IS NULL OR login ~ '^[a-zA-Z0-9_.-]{3,32}$'");
                    table.CheckConstraint("ck_users_role", "role IN ('user', 'admin')");
                    table.CheckConstraint("ck_users_verified_email", "email_verified_at IS NULL OR email IS NOT NULL");
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
                name: "ux_users_email_lower",
                table: "users",
                column: "email",
                unique: true,
                filter: "email IS NOT NULL");

            migrationBuilder.Sql(
                """CREATE UNIQUE INDEX ux_users_login_lower ON users (lower(login)) WHERE login IS NOT NULL;""");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "email_verification_tokens");

            migrationBuilder.DropTable(
                name: "password_reset_tokens");

            migrationBuilder.DropTable(
                name: "refresh_tokens");

            migrationBuilder.DropTable(
                name: "user_settings");

            migrationBuilder.DropTable(
                name: "users");
        }
    }
}
