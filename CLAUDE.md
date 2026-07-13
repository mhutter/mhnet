# mhnet Ansible

This repo contains the Ansible configurations for some personal systems.

Most of them are hosted on very cheap VPS.
I pay all of these out of my own pocket, so being conservative with sizing is a must.
I am however the sole consumer for most of these systems, so performance should not be an issue.

Systems should be low-maintenance, i.e. no manual intervention required to keep them up-to-date.

Systems should be secure by default: automated updates, minimal permissions, regular backups.

## Architecture guidelines

- dependencies (e.g. databases) co-located on the same system
- exposing HTTP services via cloudflared -> no incoming connections required
- lean setups: prefer built-in (e.g. sqlite) vs separate databases; prefer native installations vs containers
- Ubuntu (the latest LTS release, currently 26.04 "Resolute Raccoon") is used as the default operating system.

## Hostnames

Scheme: `<provider>-<purpose>`, e.g. `scw-miniflux`. Provider is a short code
(`scw` = Scaleway, `hbc` = Hetzner Cloud, `ovh` = OVH, ...); purpose is the
primary app/role name, lowercase. Append `-2`, `-3`, ... only if a provider
ends up hosting more than one instance of the same purpose.

## Layout

- `inventory/hosts.yml` — fully Ansible Vault-encrypted; hosts, groups, and all
  vars (secrets included) live here
- `inventory.example.yml` — unencrypted skeleton of the above, documenting
  every required var; keep in sync when roles gain inventory vars
- `roles/` — `common`, `firewall`, `backup`, `cloudflared`, `postgresql`,
  `dns64`, `monitoring_agent` apply broadly; `pocket_id`, `miniflux`,
  `monitoring_hub` are per-app
- `playbooks/site.yml` — main playbook, run against `all` plus per-app host
  groups; roles are tagged with their own name for selective runs
- `playbooks/bootstrap.yml` — minimal `common`-only pass for brand-new hosts
- `.vaultpass` — local vault password file (gitignored), used by
  `ansible.cfg`/`ansible-vault`

See `README.md` for details on the `backup`, `cloudflared` and monitoring
roles (onboarding a host, required vars, manual operations).

## Running

```sh
ansible-playbook playbooks/site.yml               # full run
ansible-playbook playbooks/site.yml --tags miniflux # single role
just bootstrap                                     # bootstrap a new host
ansible-vault edit inventory/hosts.yml             # edit secrets
```

## Secrets

Never generate secrets, edit vaulted inventory values, or print decrypted
vault contents yourself — hand these to the user with the exact command to
run (e.g. `ansible-vault edit inventory/hosts.yml`, `openssl rand -base64
32`).
