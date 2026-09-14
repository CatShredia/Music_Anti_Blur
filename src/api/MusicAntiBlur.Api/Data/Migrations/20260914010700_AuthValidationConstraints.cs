using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MusicAntiBlur.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AuthValidationConstraints : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddCheckConstraint(
                name: "ck_users_email_length",
                table: "users",
                sql: "email IS NULL OR (char_length(email) BETWEEN 3 AND 254)");

            migrationBuilder.AddCheckConstraint(
                name: "ck_users_password_hash",
                table: "users",
                sql: "char_length(password_hash) > 0");

            migrationBuilder.CreateIndex(
                name: "ux_evt_pending_email_active",
                table: "email_verification_tokens",
                column: "pending_email",
                unique: true,
                filter: "used_at IS NULL AND invalidated_at IS NULL AND purpose = 'bind'");

            migrationBuilder.Sql(
                """
                DROP INDEX IF EXISTS ux_users_email_lower;
                CREATE UNIQUE INDEX ux_users_email_lower ON users (lower(email)) WHERE email IS NOT NULL;
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ux_evt_pending_email_active",
                table: "email_verification_tokens");

            migrationBuilder.DropCheckConstraint(
                name: "ck_users_email_length",
                table: "users");

            migrationBuilder.DropCheckConstraint(
                name: "ck_users_password_hash",
                table: "users");

            migrationBuilder.Sql(
                """
                DROP INDEX IF EXISTS ux_users_email_lower;
                CREATE UNIQUE INDEX ux_users_email_lower ON users (email) WHERE email IS NOT NULL;
                """);
        }
    }
}
