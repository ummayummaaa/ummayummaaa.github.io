#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/lib.sh"

backup_require_command pg_dump
backup_require_command pg_dumpall
backup_require_command jq
backup_require_command gpg
backup_require_command tar
backup_require_env SUPABASE_DB_URL

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_dir="${BACKUP_OUTPUT_DIR:-${RUNNER_TEMP:-/tmp}/mediq-backups}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mediq-database.XXXXXX")"
plain_archive="$work_dir/mediq-database-$timestamp.tar.gz"
encrypted_archive="$output_dir/mediq-database-$timestamp.tar.gz.gpg"
checksum_file="$encrypted_archive.sha256"
mkdir -p "$output_dir"
chmod 700 "$work_dir"
trap 'rm -rf "$work_dir"' EXIT

pg_dump --dbname="$SUPABASE_DB_URL" --format=custom --compress=9 \
  --no-owner --no-privileges --file="$work_dir/database.dump"
pg_dump --dbname="$SUPABASE_DB_URL" --schema-only --no-owner --no-privileges \
  --file="$work_dir/schema.sql"
pg_dump --dbname="$SUPABASE_DB_URL" --data-only --format=custom --compress=9 \
  --no-owner --no-privileges --file="$work_dir/data.dump"
pg_dumpall --dbname="$SUPABASE_DB_URL" --roles-only --no-role-passwords \
  --no-owner --file="$work_dir/roles.sql"

pg_restore --list "$work_dir/database.dump" >/dev/null
pg_restore --list "$work_dir/data.dump" >/dev/null

jq -n \
  --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg project_ref "${SUPABASE_PROJECT_REF:-unknown}" \
  --arg source_revision "${GITHUB_SHA:-local}" \
  '{format_version:1,backup_type:"supabase-database",created_at_utc:$created_at,project_ref:$project_ref,source_revision:$source_revision,contents:["database.dump","schema.sql","data.dump","roles.sql"]}' \
  > "$work_dir/manifest.json"

(
  cd "$work_dir"
  shasum -a 256 database.dump schema.sql data.dump roles.sql manifest.json > checksums.txt
)
tar -C "$work_dir" -czf "$plain_archive" database.dump schema.sql data.dump roles.sql manifest.json checksums.txt
backup_encrypt "$plain_archive" "$encrypted_archive"
backup_verify_encrypted_tar "$encrypted_archive"
printf '%s  %s\n' "$(backup_sha256 "$encrypted_archive")" "$(basename "$encrypted_archive")" > "$checksum_file"

backup_upload_both "$encrypted_archive" "/MediQ Backups/database/daily/$(basename "$encrypted_archive")"
backup_upload_both "$checksum_file" "/MediQ Backups/manifests/$(basename "$checksum_file")"
printf 'database_backup=%s\nchecksum=%s\n' "$encrypted_archive" "$checksum_file"
