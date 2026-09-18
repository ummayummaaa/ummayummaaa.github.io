# Backup retention policy

This policy applies independently to the encrypted MediQ backups stored in
Dropbox and Yandex Disk.

## Retention limits

| Backup class | Location | Copies retained |
| --- | --- | ---: |
| Database, daily | `database/daily/` | 7 |
| Database, weekly | `database/weekly/` | 4 |
| Database, monthly | `database/monthly/` | 12 |
| Git, weekly | `code/weekly/` | 8 |
| Git, stable release | `code/releases/` | All |
| Supabase Storage, weekly | `storage/weekly/` | 4 |

Stable release backups are never removed automatically. Storage backups are
created only when the Storage inventory contains objects; an empty inventory is
recorded in the backup log without creating an empty archive.

## Required naming and metadata

Backup filenames must contain a UTC timestamp in `YYYYMMDDTHHMMSSZ` format.
Every encrypted archive must have a matching `.sha256` file in `manifests/`.
The manifest inside the encrypted archive must identify the backup type,
creation time, source, contents, file sizes, and checksums.

## Safe rotation sequence

Rotation is evaluated separately for Dropbox and Yandex Disk:

1. Create and validate the backup locally.
2. Encrypt it before uploading.
3. Upload the encrypted archive and its matching checksum file.
4. Confirm the remote filename and exact byte size.
5. Verify the checksum when the provider supports downloading or hashing; when
   it does not, verify the local encrypted file before upload and confirm the
   provider-reported byte size after upload.
6. Mark the new copy as verified for that provider.
7. Calculate which verified copies exceed the retention limit.
8. Produce a dry-run deletion list.
9. Delete only after an explicit approval for that deletion list.
10. Delete an archive and its matching checksum file as one logical pair.
11. Record the result, including skipped and failed operations.

If upload or verification fails, rotation for that provider stops immediately.
A failure in one provider must not prevent a successful upload to the other,
but it must never be treated as successful redundancy.

## Deletion safeguards

- Never delete the newest verified copy.
- Never rotate unverified, partially uploaded, or ambiguously named files.
- Never delete a stable release backup automatically.
- Never delete more than the dry-run list approved for that run.
- Stop if the archive and checksum cannot be matched unambiguously.
- Keep all copies while the number of verified backups is at or below the limit.
- Treat provider errors, missing metadata, and checksum mismatches as failures.

## Current baseline

As of 2026-09-18, each provider has one verified daily database backup and one
verified weekly Git backup. No retention limit has been reached, so no deletion
is currently required.
