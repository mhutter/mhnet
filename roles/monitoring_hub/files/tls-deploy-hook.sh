#!/usr/bin/env bash
# Copy the renewed certificate where the monitoring daemons can read it.
# VictoriaMetrics and VictoriaLogs re-read the files every second, so no
# restarts are needed. certbot sets RENEWED_LINEAGE.
set -euo pipefail
install -o root -g _victoria-metrics -m 0640 "$RENEWED_LINEAGE/fullchain.pem" /etc/victoria-metrics/tls/cert.pem
install -o root -g _victoria-metrics -m 0640 "$RENEWED_LINEAGE/privkey.pem" /etc/victoria-metrics/tls/key.pem
install -o root -g victorialogs -m 0640 "$RENEWED_LINEAGE/fullchain.pem" /etc/victorialogs/tls/cert.pem
install -o root -g victorialogs -m 0640 "$RENEWED_LINEAGE/privkey.pem" /etc/victorialogs/tls/key.pem
