let
  ## Clients
  rotz = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIENf5523OeX3ZEOJuAF9P5OLy+/S78UX7+xNC+O6AoD9 mh@rotz2026";
  nxzt = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIERnSasc2L5AHp+uPCc+gCwF5HoPP5i2bnwwYycYfbpn mh@nxzt";

  ## Systems
  rhea = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID1Lt8AOg3b9rjfC712BEu/IghkONzpZfqCPSB8hwhyV";

  ## Templates
  hostRhea = [
    rotz
    nxzt
    rhea
  ];
in
{ }
