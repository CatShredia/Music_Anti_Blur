using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace MusicAntiBlur.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class PlaybackState : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
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

            migrationBuilder.CreateIndex(
                name: "ix_playback_track",
                table: "playback_states",
                column: "track_id",
                filter: "track_id IS NOT NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "playback_states");
        }
    }
}
