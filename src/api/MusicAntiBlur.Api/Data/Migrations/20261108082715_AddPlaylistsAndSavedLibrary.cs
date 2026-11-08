using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MusicAntiBlur.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddPlaylistsAndSavedLibrary : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "description",
                table: "playlists",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "is_public",
                table: "playlists",
                type: "boolean",
                nullable: false,
                defaultValue: false);

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

            migrationBuilder.AddCheckConstraint(
                name: "ck_playlists_description",
                table: "playlists",
                sql: "description IS NULL OR char_length(description) <= 500");

            migrationBuilder.AddCheckConstraint(
                name: "ck_playlists_liked_private",
                table: "playlists",
                sql: "kind <> 'liked' OR NOT is_public");

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
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "saved_albums");

            migrationBuilder.DropTable(
                name: "saved_playlists");

            migrationBuilder.DropCheckConstraint(
                name: "ck_playlists_description",
                table: "playlists");

            migrationBuilder.DropCheckConstraint(
                name: "ck_playlists_liked_private",
                table: "playlists");

            migrationBuilder.DropColumn(
                name: "description",
                table: "playlists");

            migrationBuilder.DropColumn(
                name: "is_public",
                table: "playlists");
        }
    }
}
