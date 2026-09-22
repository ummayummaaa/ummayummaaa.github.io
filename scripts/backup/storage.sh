#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/lib.sh"

backup_require_command psql
backup_require_command jq
backup_require_env SUPABASE_DB_URL

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_dir="${BACKUP_OUTPUT_DIR:-${RUNNER_TEMP:-/tmp}/mediq-backups}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mediq-storage.XXXXXX")"
mkdir -p "$output_dir"
chmod 700 "$work_dir"
trap 'rm -rf "$work_dir"' EXIT

psql "$SUPABASE_DB_URL" -X -At -v ON_ERROR_STOP=1 -c \
  "with stats as (select b.id,b.name,b.public,b.file_size_limit,b.allowed_mime_types,count(o.id) object_count,coalesce(sum((o.metadata->>'size')::bigint),0) total_bytes from storage.buckets b left join storage.objects o on o.bucket_id=b.id group by b.id,b.name,b.public,b.file_size_limit,b.allowed_mime_types) select jsonb_pretty(jsonb_build_object('format_version',1,'created_at_utc',to_char(clock_timestamp() at time zone 'UTC','YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"'),'project_ref','${SUPABASE_PROJECT_REF:-unknown}','object_count',coalesce(sum(object_count),0),'total_bytes',coalesce(sum(total_bytes),0),'buckets',coalesce(jsonb_agg(to_jsonb(stats) order by id),'[]'::jsonb))) from stats;" \
  > "$work_dir/inventory.json"

object_count="$(jq -r '.object_count' "$work_dir/inventory.json")"
if test "$object_count" = "0"; then
  jq '. + {archive_created:false,archive_skip_reason:"All Storage buckets were empty."}' \
    "$work_dir/inventory.json" > "$output_dir/storage-inventory-$timestamp.json"
  printf 'storage_inventory=%s\narchive_created=false\n' "$output_dir/storage-inventory-$timestamp.json"
  exit 0
fi

backup_require_command python3
backup_require_command gpg
backup_require_command tar
backup_require_env SUPABASE_URL
backup_require_env SUPABASE_SERVICE_ROLE_KEY

psql "$SUPABASE_DB_URL" -X -At -v ON_ERROR_STOP=1 -c \
  "select coalesce(jsonb_agg(jsonb_build_object('bucket_id',bucket_id,'name',name,'size',coalesce((metadata->>'size')::bigint,0)) order by bucket_id,name),'[]'::jsonb) from storage.objects;" \
  > "$work_dir/objects.json"
mkdir -p "$work_dir/objects"
python3 "$script_dir/download_storage.py" "$work_dir/objects.json" "$work_dir/objects"
(
  cd "$work_dir"
  find objects -type f -print0 | sort -z | xargs -0 shasum -a 256 > checksums.txt
)

plain_archive="$work_dir/mediq-storage-$timestamp.tar.gz"
encrypted_archive="$output_dir/mediq-storage-$timestamp.tar.gz.gpg"
checksum_file="$encrypted_archive.sha256"
tar -C "$work_dir" -czf "$plain_archive" inventory.json objects.json objects checksums.txt
backup_encrypt "$plain_archive" "$encrypted_archive"
backup_verify_encrypted_tar "$encrypted_archive"
printf '%s  %s\n' "$(backup_sha256 "$encrypted_archive")" "$(basename "$encrypted_archive")" > "$checksum_file"
backup_upload_both "$encrypted_archive" "/MediQ Backups/storage/weekly/$(basename "$encrypted_archive")"
backup_upload_both "$checksum_file" "/MediQ Backups/manifests/$(basename "$checksum_file")"
printf 'storage_backup=%s\nchecksum=%s\n' "$encrypted_archive" "$checksum_file"
