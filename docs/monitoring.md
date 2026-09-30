# Monitoring

`services/monitoring.nix` is the hub for the Ansible fleet's push agents
(`ansible/docs/monitoring.md`): VictoriaMetrics, VictoriaLogs and Grafana, all
on loopback behind Caddy.

| Hostname            | Serves                                             |
| ------------------- | -------------------------------------------------- |
| `metrics.mhnet.app` | VictoriaMetrics, basic auth (vmagent remote_write) |
| `logs.mhnet.app`    | VictoriaLogs, basic auth (journal-upload)          |
| `grafana.mhnet.app` | Grafana UI                                         |

All three need DNS-only A/AAAA records (`docs/proxy.md`).

## Secrets

- `monitoring-password.age` — the ingest password, identical to the vault's
  `monitoring_remote_write_password`: the agents keep sending it.
- `grafana-secret-key.age` — the key `grafana.db` was encrypted with. Taken over
  from the Ansible hub, which never set one, so it is Grafana's old built-in
  default. Check on the hub:
  `sudo grep -E '^\s*secret_key' /etc/grafana/grafana.ini /usr/share/grafana/conf/defaults.ini`.

Both hold just the value; agenix-edited files end in a newline, which Grafana
trims.

## Migrating from the Ansible hub

History is not migrated; the old hub keeps it until it is decommissioned.
Grafana's state is, by copying `grafana.db` once:

1. Deploy (`just switch`). Grafana starts with an empty database and, by
   design, no admin account.
2. On the Ansible hub, stop Grafana for good — otherwise both instances
   evaluate the alert rules and every alert arrives twice — and dump the db:

   ```sh
   sudo systemctl disable --now grafana-server
   sudo sqlite3 /var/lib/grafana/grafana.db "VACUUM INTO '/tmp/grafana.db'"
   ```

3. Copy `/tmp/grafana.db` to rhea, then there:

   ```sh
   sudo systemctl stop grafana
   sudo rm -f /nix/persist/var/lib/grafana/data/grafana.db*
   sudo install -o grafana -g grafana -m 0640 grafana.db \
     /nix/persist/var/lib/grafana/data/grafana.db
   sudo systemctl start grafana
   ```

4. Point the agents at rhea (`ansible/docs/monitoring.md`).

Datasources, the dashboard and the alert rules are re-provisioned on every
start; users, contact points and notification policies come from the db.

**Version gap.** nixpkgs' Grafana (unstable, 13.1 at the time of writing) is
older than the Ansible hub's apt one (≥ 13.2), so this opens the db with a
_downgraded_ Grafana — unsupported upstream. If Grafana fails to start or the
UI misbehaves, the fallback is a fresh start: delete the db and recreate the
Telegram contact point and the notification policy in the UI.

## Backups

VictoriaMetrics is snapshotted and Grafana's db dumped with `VACUUM INTO`
before each run; the live data of both is excluded. VictoriaLogs is not backed
up.

## rhea's own metrics

`services/monitoring-agent.nix` is the metrics half of the Ansible
`monitoring_agent` role: node_exporter on loopback with the same collector
allowlist, scraped every 30s by Vector and written to VictoriaMetrics directly
on loopback, labelled `job="node"`, `instance="rhea"`. The failed-units
textfile metric is ported; the dpkg conffile one has no NixOS equivalent, so
its dashboard panel stays empty for rhea. Logs are not shipped yet.
