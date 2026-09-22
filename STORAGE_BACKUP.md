# Supabase Storage backup

The production project currently has two private Storage buckets. The checked
inventory in `supabase/storage-inventory/` records their configuration and
object counts without containing object data or credentials.

## Backup behavior

1. Read the bucket and object inventory through the PostgreSQL connection.
2. If every bucket is empty, save the inventory and do not create an empty
   archive.
3. If objects exist, require the Supabase service-role or secret key from the
   protected automation environment.
4. Download each object from the private Storage API while preserving its
   bucket and object path.
5. Verify the downloaded byte size and SHA-256 checksum.
6. Store the inventory, checksums, and objects in one archive.
7. Encrypt the archive before uploading it to either cloud provider.
8. Upload the same encrypted archive to Dropbox and Yandex Disk and verify both
   copies independently.
9. Apply the retention rules in `BACKUP_RETENTION.md` only after verification.

Credentials must never be stored in this repository. Local runs read them from
macOS Keychain; remote automation must use encrypted repository secrets.

## Current status

The inventory recorded on 2026-09-22 contains two private buckets and zero
objects. No Storage archive was created because there was no object data to
protect.
