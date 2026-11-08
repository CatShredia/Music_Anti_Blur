using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MusicAntiBlur.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddGenresAndSearchHistory : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
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

            migrationBuilder.CreateIndex(
                name: "ix_album_genres_genre",
                table: "album_genres",
                column: "genre_id");

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
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "album_genres");

            migrationBuilder.DropTable(
                name: "search_history");

            migrationBuilder.DropTable(
                name: "track_genres");

            migrationBuilder.DropTable(
                name: "genres");
        }
    }
}
