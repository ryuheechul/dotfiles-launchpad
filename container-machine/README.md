# container-machine

[Apple `container`](https://github.com/apple/container)
[machine](https://github.com/apple/container/blob/main/docs/container-machine.md)
images for these dotfiles - the machine cousin of the root Docker route.
Images are user-agnostic: no host account is baked in; a first-boot service
grafts the template home onto whatever account the machine runtime creates
from your host user.

Each supported OS is a flavor directory:

- [`ubuntu/`](./ubuntu/) - `dotfiles-cm`, the shipped flavor: Ubuntu 24.04
  with systemd as `/sbin/init` and dotfiles baked through `setup.sh`
  (single-user nix + home-manager). See its
  [README](./ubuntu/README.md) for the user model, build, and launch flow.
- [`nixos/`](./nixos/) - planned: `dotfiles-nixos-cm` on top of
  [ryuheechul/provision](https://github.com/ryuheechul/provision)'s
  published `nixos-cm` base, which also carries a general
  [troubleshoot section](https://github.com/ryuheechul/provision/blob/main/apple/container-machine/README.md#troubleshoot)
  for machine runtime issues.
