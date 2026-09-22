# PostgreSQL

The `postgresql` role installs the server from apt and hooks it into the
backup role: a pre-backup hook dumps every database (custom format) plus the
globals to `/var/backups/postgresql`, which is registered as a backup path.
The dumps are the restore artifact; PGDATA is not backed up raw.

## Tuning

The role renders `conf.d/10-tuning.conf` into the cluster's config directory,
with the memory settings derived from the host's RAM: `shared_buffers` at 20%
(below the usual 25%, because on these hosts the app is the other large
consumer), `effective_cache_size` at 50%, `maintenance_work_mem` at 5% capped
at 256 MB, plus `max_connections = 20` and SSD-appropriate
`random_page_cost`/`effective_io_concurrency`. Every value is a `postgresql_*`
variable that can be overridden per host, and `postgresql_extra_settings`
appends anything else. The packaged `postgresql.conf` is left untouched (the
role only checks that it reads `conf.d`). Changing any of this restarts
PostgreSQL, so the first run of this on an existing host briefly takes its
app's database down.

## App databases

App roles include the role for the server and then create their database:

```yaml
- name: Install PostgreSQL
  ansible.builtin.include_role:
    name: postgresql

- name: Create my-app database
  ansible.builtin.include_role:
    name: postgresql
    tasks_from: database
  vars:
    postgresql_database_name: myapp
```

The owning role defaults to the database name (override with
`postgresql_database_owner`) and gets no password: app daemons run as a
matching system user and connect over the local socket, where Debian's
default `local all all peer` rule authenticates them.
