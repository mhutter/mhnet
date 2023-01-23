#!/usr/bin/env bash
set -e -u -o pipefail

function list() {
  hcloud server list -o json | \
  jsonnet --tla-code sshPort="$SSH_PORT" inventory.jsonnet
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

