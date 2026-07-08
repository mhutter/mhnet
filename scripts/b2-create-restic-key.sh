#!/usr/bin/env bash
#
# Create a B2 application key for a host, restricted to the "mhnet-restic"
# bucket and the "<hostname>/" file name prefix.
#
# Usage:   b2-create-restic-key.sh <hostname>
#
# Requires B2_APPLICATION_KEY_ID and B2_APPLICATION_KEY in the environment,
# holding a key with the "writeKeys" and "listBuckets" capabilities
# (e.g. the master key).

set -euo pipefail

BUCKET_NAME="mhnet-restic"
# deleteFiles is included because restic needs it to remove stale lock files
# and to prune old snapshots.
CAPABILITIES='["listBuckets","listFiles","readFiles","writeFiles","deleteFiles"]'

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "Usage: $(basename "$0") <hostname>" >&2
  exit 64
fi
hostname=$1
# keyName must be alphanumeric or '-'; the namePrefix keeps the real hostname
key_name=$(tr -c 'a-zA-Z0-9-' '-' <<<"$hostname" | tr -s '-')
key_name=${key_name%-}

: "${B2_APPLICATION_KEY_ID:?must be set}"
: "${B2_APPLICATION_KEY:?must be set}"

# Fail with B2's error message (curl -f would discard the response body)
check() {
  if [ "$(jq -r '.status // empty' <<<"$1")" ]; then
    echo "B2 API error: $(jq -r '"\(.status) \(.code): \(.message)"' <<<"$1")" >&2
    exit 1
  fi
}

auth=$(curl -sS -u "${B2_APPLICATION_KEY_ID}:${B2_APPLICATION_KEY}" \
  https://api.backblazeb2.com/b2api/v2/b2_authorize_account)
check "$auth"
api_url=$(jq -re .apiUrl <<<"$auth")
token=$(jq -re .authorizationToken <<<"$auth")
account_id=$(jq -re .accountId <<<"$auth")

buckets=$(curl -sS -H "Authorization: $token" \
  -d "$(jq -n --arg a "$account_id" --arg b "$BUCKET_NAME" \
    '{accountId: $a, bucketName: $b}')" \
  "$api_url/b2api/v2/b2_list_buckets")
check "$buckets"
bucket_id=$(jq -re '.buckets[0].bucketId' <<<"$buckets")

key=$(curl -sS -H "Authorization: $token" \
  -d "$(jq -n \
    --arg a "$account_id" --arg b "$bucket_id" --arg h "$hostname" \
    --arg k "$key_name" --argjson c "$CAPABILITIES" \
    '{accountId: $a, bucketId: $b, keyName: $k,
      namePrefix: ($h + "/"), capabilities: $c}')" \
  "$api_url/b2api/v2/b2_create_key")
check "$key"

jq -r '"backup_b2_account_id: \(.applicationKeyId)\nbackup_b2_account_key: \(.applicationKey)"' <<<"$key"
