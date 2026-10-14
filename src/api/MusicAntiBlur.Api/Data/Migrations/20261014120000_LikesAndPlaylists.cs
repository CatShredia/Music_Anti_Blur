using System;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.EntityFrameworkCore.Migrations;
using MusicAntiBlur.Api.Data;

#nullable disable

namespace MusicAntiBlur.Api.Data.Migrations
{
    /// <inheritdoc />
    [DbContext(typeof(AppDbContext))]
    [Migration("20261014120000_LikesAndPlaylists")]
    public class LikesAndPlaylists : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
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
                name: "playlists",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    user_id = table.Column<Guid>(type: "uuid", nullable: false),
                    title = table.Column<string>(type: "text", nullable: false),
                    kind = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_playlists", x => x.id);
                    table.CheckConstraint("ck_playlists_kind", "kind IN ('liked', 'user')");
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

            migrationBuilder.CreateIndex(
                name: "ix_liked_tracks_track",
                table: "liked_tracks",
                column: "track_id");

            migrationBuilder.CreateIndex(
                name: "ix_liked_tracks_user_liked_at",
                table: "liked_tracks",
                columns: new[] { "user_id", "liked_at" });

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
                name: "ix_playlists_user",
                table: "playlists",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "ux_playlists_user_liked",
                table: "playlists",
                column: "user_id",
                unique: true,
                filter: "kind = 'liked'");

            migrationBuilder.Sql("""
                INSERT INTO playlists (id, user_id, title, kind, created_at, updated_at)
                SELECT gen_random_uuid(), u.id, 'Мне нравится', 'liked', NOW(), NOW()
                FROM users u
                WHERE NOT EXISTS (
                    SELECT 1 FROM playlists p WHERE p.user_id = u.id AND p.kind = 'liked'
                );
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(name: "liked_tracks");
            migrationBuilder.DropTable(name: "playlist_tracks");
            migrationBuilder.DropTable(name: "playlists");
        }
    }
}
