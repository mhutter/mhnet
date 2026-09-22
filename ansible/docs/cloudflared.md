# Cloudflare tunnels

Tunnel creation is a one-time dashboard step (create the tunnel, note its ID
and token). Everything else is the `cloudflared` role: the connector service
on the host, the per-hostname ingress configuration pushed to the Cloudflare
API — dashboard edits get overwritten — and the DNS CNAME `<app-host>` →
`<tunnel-id>.cfargotunnel.com`.

App roles include the role for the connector and then expose their hostname:

```yaml
- name: Install the Cloudflare tunnel connector
  ansible.builtin.include_role:
    name: cloudflared

- name: Expose my-app through the Cloudflare tunnel
  ansible.builtin.include_role:
    name: cloudflared
    tasks_from: expose
  vars:
    cloudflared_expose_hostname: my-app.example.com
    cloudflared_expose_service: "http://localhost:8080"
```

Hostnames are upserted into the tunnel's ingress, so several roles can share
one tunnel; removing a role leaves its ingress entry and DNS record behind
(clean up in the dashboard).

Required inventory vars: `cloudflare_account_id` and `cloudflare_api_token`
(API token with Account > Cloudflare Tunnel > Edit and Zone > DNS > Edit) at
the `all` level; `cloudflared_tunnel_id` and `cloudflared_tunnel_token` per
host.
