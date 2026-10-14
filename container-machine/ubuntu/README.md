# dotfiles-cm container machine

Ubuntu-based [container machine](https://github.com/apple/container/blob/main/docs/container-machine.md)
image with dotfiles pre-baked as a template home - the machine cousin of the
Docker route in the root README. The image carries no host identity: a
first-boot service grafts the template onto whatever account the machine
runtime creates from your host user.

## Use the published image

```sh
make launch-published       # pull the CI image, create (or reuse) + wait for first boot
make run                    # shell in
```

Make targets (from this directory): `make launch`, `make launch-published`
(pulls the CI image first), `make run`, `make stop`, `make delete`, and
`make build` for a local image - see the [Makefile](./Makefile).

The image is published on demand to
`ghcr.io/ryuheechul/dotfiles-launchpad/dotfiles-cm` (tags `latest` and
`sha-<short>`) by the dispatch-only
[dotfiles-cm workflow](../../.github/workflows/dotfiles-cm-publish.yml).

## Build locally

```sh
make build
CONTAINER_IMAGE=local/dotfiles-cm:latest make launch
```

The Dockerfile takes the repo root as its build context (it clones the
`dotfiles` submodule's pinned SHA, so `~/dotfiles` lands as a real git
repo on a `pinned-<sha7>` branch); the Makefile resolves that context, its
own location, and the pin, so `make build` works from any directory. The image
builds with `container build` straight into the machine runtime's image
store: this is a container machine, so stay on the same tooling - no docker
involved (CI builds the same Dockerfile with `docker buildx` instead - see
[Local (macOS) vs CI builds](../README.md#local-macos-vs-ci-builds)).
Builder networking only works once
every service runs the same CLI version; after a CLI upgrade, restart the
whole stack (`container system stop` / `start`, repointing any stale service
plists under `~/Library/Application Support/com.apple.container/`) if
in-build DNS and TCP fail. The image is multi-stage: the provisioned rootfs
is copied into the final image as a single layer, which keeps it at ~7G
instead of the ~12G a single-stage stack of the setup/GC/purge layers
produces (machine disks shrink the same way, ~15G instead of ~23G).

## How it works

The design in one line: bake whatever can be baked at build time, and
defer to a one-time first-boot service whatever needs the real user (who
only exists at runtime, and is never whoever ran the build):

- **baked**: the dotfiles clone, home-manager's generated config, and the
  nix toolchain - all identity-free, kept as a template home at
  `/var/lib/dotfiles-cm/baked-home` (built as a throwaway `dotted`
  account that is purged from the image at the end of the build; nothing
  under `/home`, so the runtime can always provision `/home/<name>`).
- **deferred to first boot**: the runtime creates the real account (your
  host user) on boot; `dotfiles-cm-firstboot.service` waits for it (the
  runtime writes sudoers last), grafts the template onto the account,
  rewrites the baked paths, hands over `/nix`, then re-runs
  `hm.sh switch` + `configuration.sh` so every generated file carries the
  real identity.
- **one-time**: a verify gate (no baked paths left, `nix` on PATH,
  `my_dot_d` rebased) must pass before the marker
  `/var/lib/dotfiles-cm/firstboot.done` is written; on failure the unit
  retries on the next boot, always from a clean re-graft.

First boot takes a few minutes (template copy + chown + hm eval/build);
`bin/launch.sh` waits for the marker after creating a machine
(`DOTFILES_CM_NO_WAIT=1` skips). Knobs: image via `CONTAINER_IMAGE`,
machine name via `MACHINE` (make) or `CONTAINER_MACHINE_NAME` (script),
default `dotfiles-cm`. Progress and failures:
`container machine run -n dotfiles-cm --root journalctl -u dotfiles-cm-firstboot`

The full detail - the sudoers wait, the single-user nix handover, the
zshenv quirk, and the nixos flavor's take on all of this - lives in the
shared [how-it-works.md](../how-it-works.md).

## Clean up

```sh
make delete
```
