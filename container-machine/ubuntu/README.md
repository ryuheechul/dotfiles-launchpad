# dotfiles-cm container machine

Ubuntu-based [container machine](https://github.com/apple/container/blob/main/docs/container-machine.md)
image with dotfiles pre-baked as a template home - the machine cousin of the
Docker route in the root README. The image carries no host identity: a
first-boot service grafts the template onto whatever account the machine
runtime creates from your host user.

## Flavor status

- `dotfiles-cm` - non-NixOS (this directory): Ubuntu 24.04 with systemd as
  `/sbin/init` plus dotfiles via `setup.sh` (same recipe as the root
  Dockerfile). Published on demand to
  `ghcr.io/ryuheechul/dotfiles-launchpad/dotfiles-cm` (tags `latest` and
  `sha-<short>`) by the dispatch-only
  [dotfiles-cm workflow](../../.github/workflows/dotfiles-cm-publish.yml).
- `dotfiles-nixos-cm` - planned: NixOS flavor baked on top of
  [ryuheechul/provision](https://github.com/ryuheechul/provision)'s prebuilt
  `ghcr.io/ryuheechul/provision/nixos-cm` base.

## Use the published image

```sh
./bin/launch.sh             # create the machine (or reuse it if it exists)
container machine run -n dotfiles-cm
```

Make targets (from this directory): `make launch`, `make run`, `make stop`,
`make delete`, and `make build` for a local image - see the
[Makefile](./Makefile).

## Build locally

```sh
make build
CONTAINER_IMAGE=local/dotfiles-cm:latest make launch
```

The Dockerfile takes the repo root as its build context (it COPYies the
`dotfiles` submodule); the Makefile resolves both that context and its own
location, so `make build` works from any directory. The image
builds with `container build` straight into the machine runtime's image
store: this is a container machine, so stay on the same tooling - no docker
involved. CI builds the same Dockerfile with `docker buildx build` on GitHub
runners, which have no apple `container`. Builder networking only works once
every service runs the same CLI version; after a CLI upgrade, restart the
whole stack (`container system stop` / `start`, repointing any stale service
plists under `~/Library/Application Support/com.apple.container/`) if
in-build DNS and TCP fail. The image is multi-stage: the provisioned rootfs
is copied into the final image as a single layer, which keeps it at ~7G
instead of the ~12G a single-stage stack of the setup/GC/purge layers
produces (machine disks shrink the same way, ~15G instead of ~23G).

## How it works

- user provisioning happens on boot inside the machine runtime itself (it
  edits `/etc/passwd`, idempotent) - nothing image-side is needed for the
  account itself. The account matches your host user (name/uid/gid, home
  `/home/<name>`), while your mac home mounts separately under
  `/Users/<name>`. Its login shell comes from the image's
  `/etc/adduser.conf` `DSHELL`, set to `/bin/zsh` here, so
  `container machine run` starts in zsh with the dotfiles env chain.
- **the image is user-agnostic**: the dotfiles are baked as a template home
  at `/var/lib/dotfiles-cm/baked-home` (built as a throwaway `dotted`
  account that is purged from the image at the end of the build), so no
  baked account ever holds your uid/username - the runtime would otherwise
  refuse to provision against it. The base image's `ubuntu` (uid 1000)
  account is dropped for the same reason on linux hosts.
- **first boot grafts the template** (`dotfiles-cm-firstboot.service` +
  `/usr/local/sbin/dotfiles-cm-firstboot`): waits for the runtime's user
  setup (it writes sudoers last), replaces the fresh skel home with the
  template, rewrites the baked path in text files and absolute symlinks,
  drops stale `.zwc` caches, hands the baked `/nix` tree to the account
  (single-user nix chmods state dirs on every store open, which only the
  owner may do - NixOS/nix#3435), then re-runs `hm.sh switch` +
  `configuration.sh` as the runtime account so home-manager regenerates its
  store files with the real home. A verify gate (no baked paths left,
  `nix` on PATH, `my_dot_d` rebased) must pass before the marker
  `/var/lib/dotfiles-cm/firstboot.done` is written; on failure the unit
  retries on the next boot, always from a clean re-graft.
- first boot takes a few minutes (template copy + chown + hm eval/build);
  `bin/launch.sh` waits for the marker after creating a machine
  (`DOTFILES_CM_NO_WAIT=1` skips). Progress and failures:
  `container machine run -n dotfiles-cm --root journalctl -u dotfiles-cm-firstboot`
- dotfiles: copy the submodule, clean the Ubuntu skel files home-manager
  would refuse to overwrite, run `setup.sh` (with the same `SKIP_*` guards as
  the root Dockerfile), then `nix-collect-garbage -d`. The template home (~2G)
  stays in the image as the pristine graft source; each machine keeps a
  second copy as its live home.
- `/etc/zsh/zshenv` exports `USER`/`LOGNAME`: machine exec passes only a
  hardcoded `PATH` (no image `ENV`), zsh derives `HOME`/`LOGNAME` from passwd
  but never `USER`, and nix's `profile.d/nix.sh` no-ops without it - skipping
  it would drop `~/.nix-profile/bin` from every shell. (Ubuntu zsh reads
  `/etc/zsh/zshenv`, not `/etc/zshenv`.)
- Knobs: image via `CONTAINER_IMAGE`, machine name via
  `CONTAINER_MACHINE_NAME` (default `dotfiles-cm`).

## Clean up

```sh
container machine delete dotfiles-cm
```
