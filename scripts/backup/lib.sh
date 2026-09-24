#!/usr/bin/env bash

set -euo pipefail

backup_die() {
  printf 'backup error: %s\n' "$*" >&2
  exit 1
}

backup_require_command() {
  command -v "$1" >/dev/null 2>&1 || backup_die "required command is missing: $1"
}

backup_require_env() {
  test -n "${!1:-}" || backup_die "required environment variable is missing: $1"
}

backup_sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

backup_encrypt() {
  local source_file="$1"
  local encrypted_file="$2"
  backup_require_env BACKUP_ENCRYPTION_KEY
  printf '%s' "$BACKUP_ENCRYPTION_KEY" |
    gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
      --symmetric --cipher-algo AES256 --s2k-mode 3 \
      --s2k-digest-algo SHA512 --compress-algo none \
      --output "$encrypted_file" "$source_file"
}

backup_verify_encrypted_tar() {
  local encrypted_file="$1"
  printf '%s' "$BACKUP_ENCRYPTION_KEY" |
    gpg --batch --pinentry-mode loopback --passphrase-fd 0 \
      --decrypt "$encrypted_file" 2>/dev/null | tar -tzf - >/dev/null
}

backup_dropbox_access_token() {
  if test -n "${DROPBOX_ACCESS_TOKEN:-}"; then
    printf '%s' "$DROPBOX_ACCESS_TOKEN"
    return 0
  fi

  backup_require_env DROPBOX_APP_KEY
  backup_require_env DROPBOX_APP_SECRET
  backup_require_env DROPBOX_REFRESH_TOKEN

  local response access_token
  response="$(curl --fail --silent --show-error \
    --user "$DROPBOX_APP_KEY:$DROPBOX_APP_SECRET" \
    --data-urlencode 'grant_type=refresh_token' \
    --data-urlencode "refresh_token=$DROPBOX_REFRESH_TOKEN" \
    https://api.dropboxapi.com/oauth2/token)"
  access_token="$(jq -r '.access_token // empty' <<<"$response")"
  test -n "$access_token" || backup_die "Dropbox did not return an access token"
  printf '%s' "$access_token"
}

backup_upload_dropbox() {
  local local_file="$1"
  local remote_path="$2"
  local local_size response remote_size access_token
  access_token="$(backup_dropbox_access_token)"
  local_size="$(stat -f '%z' "$local_file" 2>/dev/null || stat -c '%s' "$local_file")"
  response="$(curl --fail --silent --show-error \
    -X POST https://content.dropboxapi.com/2/files/upload \
    -H "Authorization: Bearer $access_token" \
    -H 'Content-Type: application/octet-stream' \
    -H "Dropbox-API-Arg: $(jq -nc --arg path "$remote_path" '{path:$path,mode:"add",autorename:false,mute:false,strict_conflict:true}')" \
    --data-binary "@$local_file")"
  remote_size="$(jq -r '.size // empty' <<<"$response")"
  unset access_token
  test "$remote_size" = "$local_size" || backup_die "Dropbox size verification failed for $remote_path"
}

backup_upload_yandex() {
  local local_file="$1"
  local remote_path="$2"
  local local_size upload_response upload_url metadata remote_size
  backup_require_env YANDEX_OAUTH_TOKEN
  local_size="$(stat -f '%z' "$local_file" 2>/dev/null || stat -c '%s' "$local_file")"
  upload_response="$(curl --fail --silent --show-error --get \
    -H "Authorization: OAuth $YANDEX_OAUTH_TOKEN" \
    --data-urlencode "path=$remote_path" \
    --data-urlencode 'overwrite=false' \
    https://cloud-api.yandex.net/v1/disk/resources/upload)"
  upload_url="$(jq -r '.href // empty' <<<"$upload_response")"
  test -n "$upload_url" || backup_die "Yandex Disk did not return an upload URL"
  curl --fail --silent --show-error --upload-file "$local_file" "$upload_url" >/dev/null
  metadata="$(curl --fail --silent --show-error --get \
    -H "Authorization: OAuth $YANDEX_OAUTH_TOKEN" \
    --data-urlencode "path=$remote_path" \
    --data-urlencode 'fields=size,path,name' \
    https://cloud-api.yandex.net/v1/disk/resources)"
  remote_size="$(jq -r '.size // empty' <<<"$metadata")"
  test "$remote_size" = "$local_size" || backup_die "Yandex Disk size verification failed for $remote_path"
}

backup_upload_both() {
  local local_file="$1"
  local remote_path="$2"
  if test "${BACKUP_SKIP_UPLOAD:-0}" = "1"; then
    return 0
  fi
  backup_upload_dropbox "$local_file" "$remote_path"
  backup_upload_yandex "$local_file" "$remote_path"
}
