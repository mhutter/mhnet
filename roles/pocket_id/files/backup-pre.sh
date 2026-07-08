#!/usr/bin/env bash
# Produce a consistent copy of the pocket-id SQLite database.
# VACUUM INTO refuses to overwrite, so remove the previous dump first.
set -euo pipefail
dst=/var/lib/pocket-id/backup/pocket-id.db
rm -f "$dst"
sqlite3 /var/lib/pocket-id/data/pocket-id.db "VACUUM INTO '$dst'"
