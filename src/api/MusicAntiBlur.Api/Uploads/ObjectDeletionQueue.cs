using MusicAntiBlur.Api.Data;
using MusicAntiBlur.Api.Data.Entities;

namespace MusicAntiBlur.Api.Uploads;

public static class ObjectDeletionQueue
{
    public static void Enqueue(AppDbContext db, string bucketKey, Guid? ownerUserId)
    {
        if (db.ObjectDeletions.Local.Any(o => o.BucketKey == bucketKey && o.Status != "done") ||
            db.ObjectDeletions.Any(o => o.BucketKey == bucketKey && o.Status != "done"))
        {
            return;
        }

        db.ObjectDeletions.Add(new ObjectDeletion
        {
            Id = Guid.NewGuid(),
            OwnerUserId = ownerUserId,
            BucketKey = bucketKey,
            Status = "pending",
            NextAttemptAt = DateTimeOffset.UtcNow,
            CreatedAt = DateTimeOffset.UtcNow
        });
    }
}
