# dotfiles launchpad

This repository is to:
- demonstrate examples of bootstrapping [dotfiles](https://github.com/ryuheechul/dotfiles)
- test its usability
- package it into a useful form (like a docker image)

## with Docker

Builds an image that bootstraps dotfiles via single-user nix + home-manager
(the same path [dotfiles](https://github.com/ryuheechul/dotfiles)'s `setup.sh`
uses for GitHub Codespaces).

### Build
`$ make build`

### Test and play around
`$ make dev`

> Uses `docker compose` (Compose v2). A podman setup exposing the `docker` CLI
> works too.

## with Apple container machine

`dotfiles-cm` - a user-agnostic machine image: Ubuntu + systemd with the
dotfiles pre-baked, grafted onto your host account on first boot. See
[`container-machine/`](./container-machine/) for flavors, the user model,
and build/publish details.

```sh
$ ./container-machine/ubuntu/bin/launch.sh  # create (or reuse) + wait for first boot
$ container machine run -n dotfiles-cm
```

## with Lima

A throwaway Ubuntu VM provisioned by dotfiles' own `linux.sh` +
`configuration.sh`, the modern replacement for the old Vagrant box. Needs
[Lima](https://lima-vm.io) >= 1.0.

### Test

```sh
$ limactl start --name dotfiles lima.yaml
$ limactl shell dotfiles zsh

# and enjoy all the packages and configuration that dotfiles prepares,
# such as tmux, nvim, lf
```

### Clean up
`$ limactl delete -f dotfiles`
