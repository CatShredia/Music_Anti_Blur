using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MusicAntiBlur.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class AddTrackSoftDelete : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ux_tracks_album_number",
                table: "tracks");

            migrationBuilder.DropIndex(
                name: "ux_tracks_isrc",
                table: "tracks");

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "deleted_at",
                table: "tracks",
                type: "timestamp with time zone",
                nullable: true);

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
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "ix_tracks_deleted_at",
                table: "tracks");

            migrationBuilder.DropIndex(
                name: "ux_tracks_album_number",
                table: "tracks");

            migrationBuilder.DropIndex(
                name: "ux_tracks_isrc",
                table: "tracks");

            migrationBuilder.DropColumn(
                name: "deleted_at",
                table: "tracks");

            migrationBuilder.CreateIndex(
                name: "ux_tracks_album_number",
                table: "tracks",
                columns: new[] { "album_id", "track_number" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ux_tracks_isrc",
                table: "tracks",
                column: "isrc",
                unique: true,
                filter: "isrc IS NOT NULL");
        }
    }
}
