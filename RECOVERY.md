# Recovery verification

The encrypted database backup created on 2026-09-18 was restored into an
isolated local PostgreSQL 17 instance on 2026-09-22. Production was not changed.

## Verified results

- The encrypted archive checksum matched its `.sha256` file.
- The archive decrypted successfully and its tar structure was readable.
- The custom-format database and data dumps passed `pg_restore --list`.
- The restored database contained all 27 Auth tables and all 3 Auth users.
- The restored `public` schema contained all 16 application tables.
- The restored database contained 24 public RLS policies and 5 public triggers.
- Storage metadata restored with 0 objects, matching the captured inventory.
- The Dropbox copy had the exact expected size and SHA-256 checksum.

The vanilla PostgreSQL restore reported only the expected absence of the
Supabase-managed `supabase_vault` extension. A target Supabase project provides
that extension. This limitation does not affect the application tables, Auth
user count, RLS policies, triggers, or Storage metadata verified above.

## Safe restore order

1. Prepare a separate Supabase test project; never restore first into
   production.
2. Verify the encrypted archive checksum.
3. Decrypt the archive into a protected temporary directory.
4. Review `manifest.json` and verify `checksums.txt`.
5. Restore managed roles only when the target environment requires them.
6. Restore `database.dump` with ownership and ACL restoration disabled.
7. Verify Auth counts without printing user records.
8. Verify public table, function, policy, and trigger counts.
9. Verify the Storage inventory and object checksums.
10. Delete all plaintext temporary files after verification.

The Yandex Disk chain must be re-downloaded and restored when the Mac is
unlocked. The previously verified remote size matches the encrypted source, but
that metadata check alone is not recorded as a full download-and-restore test.
