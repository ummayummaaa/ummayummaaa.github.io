#!/usr/bin/env bash

set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/lib.sh"

backup_require_command git
backup_require_command jq
backup_require_command gpg
backup_require_command tar

repo_dir="${BACKUP_REPOSITORY_DIR:-${GITHUB_WORKSPACE:-$(pwd)}}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output_dir="${BACKUP_OUTPUT_DIR:-${RUNNER_TEMP:-/tmp}/mediq-backups}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/mediq-git.XXXXXX")"
plain_archive="$work_dir/mediq-git-$timestamp.tar.gz"
encrypted_archive="$output_dir/mediq-git-$timestamp.tar.gz.gpg"
checksum_file="$encrypted_archive.sha256"
mkdir -p "$output_dir"
chmod 700 "$work_dir"
trap 'rm -rf "$work_dir"' EXIT

git -C "$repo_dir" fsck --full
git clone --mirror "$repo_dir" "$work_dir/repository.git" >/dev/null
git -C "$repo_dir" bundle create "$work_dir/repository.bundle" --all
git -C "$repo_dir" bundle verify "$work_dir/repository.bundle" >/dev/null

jq -n \
  --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repository "${GITHUB_REPOSITORY:-local}" \
  --arg commit "$(git -C "$repo_dir" rev-parse HEAD)" \
  --argjson branches "$(git -C "$repo_dir" for-each-ref --format='%(refname:short)' refs/heads refs/remotes | jq -Rsc 'split("\n")[:-1]')" \
  --argjson tags "$(git -C "$repo_dir" tag --list | jq -Rsc 'split("\n")[:-1]')" \
  '{format_version:1,backup_type:"git",created_at_utc:$created_at,repository:$repository,commit:$commit,branches:$branches,tags:$tags}' \
  > "$work_dir/manifest.json"
(
  cd "$work_dir"
  shasum -a 256 repository.bundle manifest.json > checksums.txt
)
tar -C "$work_dir" -czf "$plain_archive" repository.git repository.bundle manifest.json checksums.txt
backup_encrypt "$plain_archive" "$encrypted_archive"
backup_verify_encrypted_tar "$encrypted_archive"
printf '%s  %s\n' "$(backup_sha256 "$encrypted_archive")" "$(basename "$encrypted_archive")" > "$checksum_file"

backup_upload_both "$encrypted_archive" "/MediQ Backups/code/weekly/$(basename "$encrypted_archive")"
backup_upload_both "$checksum_file" "/MediQ Backups/manifests/$(basename "$checksum_file")"
printf 'git_backup=%s\nchecksum=%s\n' "$encrypted_archive" "$checksum_file"
