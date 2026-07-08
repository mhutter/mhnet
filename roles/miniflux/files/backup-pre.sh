#!/usr/bin/env bash
set -euo pipefail

# The redirect happens in this (root) shell, so postgres itself never needs
# write access to the root-owned dump directory.
dst=/var/backups/miniflux/miniflux.dump
rm -f "$dst"
runuser -u postgres -- pg_dump --format=custom miniflux > "$dst"
