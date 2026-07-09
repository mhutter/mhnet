#!/usr/bin/env bash
set -euo pipefail

# Dumps every database plus the globals (roles, tablespaces), so app roles
# never need their own hooks. The redirects happen in this (root) shell, so
# postgres itself never needs write access to the root-owned dump directory.
dst=/var/backups/postgresql
rm -f "$dst"/*.dump "$dst"/globals.sql
runuser -u postgres -- pg_dumpall --globals-only > "$dst/globals.sql"
runuser -u postgres -- psql --no-align --tuples-only \
  --command 'SELECT datname FROM pg_database WHERE NOT datistemplate' \
  | while read -r db; do
      runuser -u postgres -- pg_dump --format=custom "$db" > "$dst/$db.dump"
    done
