#!/usr/bin/env bash
set -e -u -o pipefail

function list() {
  hcloud server list -o json | jq --arg ssh_port "$SSH_PORT" '
  . as $root |
  map({ name, key: .labels.role })
    | group_by(.key)
    | map({
        key: .[0].key,
        value: { hosts: map(.name) },
      })
    | from_entries
    | ._meta.hostvars = ($root | map({key: .name, value: {
        ansible_host: .private_net[0].ip,
      }}) | from_entries)
    | .all.vars = {
      ansible_port: $ssh_port,
      ssh_port: $ssh_port,
    }
  '
}

function host() {
  hcloud server describe "$1" -o json | jq '
    {
      ansible_host: .private_net[0].ip,
    }
  '
}

function usage() {
  echo >&2 "usage: $0 [--list|--host HOST]"
  exit 1
}

case "$1" in
  --list)
    list
    ;;
  --host)
    host "$2"
    ;;
  *)
    usage
    ;;
esac

