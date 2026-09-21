# rhea configuration

## Secrets

`secrets.nix` is keyed on the host's ssh key from step 5. From the devShell:

```sh
nix develop -c agenix -e <secret>.age
nix develop -c agenix -r                   # rekey after changing recipients
```
