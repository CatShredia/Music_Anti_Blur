using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace MusicAntiBlur.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddTwoFactorLoginEventsQuotas : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
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

            migrationBuilder.CreateIndex(
                name: "ix_login_events_at",
                table: "login_events",
                column: "at");

            migrationBuilder.CreateIndex(
                name: "ix_login_events_user_at",
                table: "login_events",
                columns: new[] { "user_id", "at", "id" });

            migrationBuilder.CreateIndex(
                name: "ux_recovery_codes_user_hash",
                table: "user_recovery_codes",
                columns: new[] { "user_id", "code_hash" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "data_protection_keys");

            migrationBuilder.DropTable(
                name: "login_events");

            migrationBuilder.DropTable(
                name: "user_quotas");

            migrationBuilder.DropTable(
                name: "user_recovery_codes");

            migrationBuilder.DropTable(
                name: "user_two_factor");
        }
    }
}
