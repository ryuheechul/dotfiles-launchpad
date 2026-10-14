# dotfiles-nixos-cm container machine

NixOS-based [container machine](https://github.com/apple/container/blob/main/docs/container-machine.md)
image with dotfiles pre-baked as a template home - the machine cousin of the
Docker route in the root README, built on
[ryuheechul/provision](https://github.com/ryuheechul/provision)'s prebuilt
`ghcr.io/ryuheechul/provision/nixos-cm` base (systemd as init, multi-user
nix). The image carries no host identity: a first-boot service grafts the
template onto whatever account the machine runtime creates from your host
user.

Three options, most convenient first:

## a) Use the published image

```sh
make launch-published       # pull the CI image, create (or reuse) + wait for first boot
make run                    # shell in
```

Make targets (from this directory): `make launch`, `make launch-published`
(pulls the CI image first), `make run`, `make stop`, `make delete` - see the
[Makefile](./Makefile).

The image is published on demand to
`ghcr.io/ryuheechul/dotfiles-launchpad/dotfiles-nixos-cm` (tags `latest`
and `sha-<short>`) by the dispatch-only
[dotfiles-nixos-cm workflow](../../.github/workflows/dotfiles-nixos-cm-publish.yml).

Caveat: the published image is not fully pre-built. `nixos-rebuild` needs a
booted machine, so only the home-manager half is baked in; the NixOS system
itself is still built on the machine's first boot (expect a minute or two of
downloading and building before the first-boot marker lands - details under
[How the image works](#how-the-image-works-options-a-and-c)).

## b) Skip this image, use provision/nixos-cm

Everything the flavor does exists to make one *shared* image usable by any
host user: nothing identity-specific is baked in, and a first-boot service
grafts your dotfiles onto the account the machine runtime creates. If you
provision the machine yourself, none of that machinery is required - a plain
[provision/nixos-cm](https://github.com/ryuheechul/provision/tree/main/apple/container-machine/nixos)
base plus your own clone already gets you the same dotfiles:

```sh
# create machine with built image
container machine create ghcr.io/ryuheechul/provision/nixos-cm:latest --name my-nixos

# shell in as your account
container machine run -n my-nixos

# clone my dotfiles or use your own dotfiles (that uses nixpkgs or nixos)
git clone https://github.com/ryuheechul/dotfiles ~/dotfiles

# cd and run the bootstrap processes
cd ~/dotfiles
# nixos switch and home-manager switch
./bootstrap/foundation/nixos/switch.sh
# non nix configurations
./bootstrap/configuration.sh
```

Option a's first-boot service automates exactly these steps clone-free:
it grafts the already-baked `~/dotfiles` and runs `switch.sh` +
`configuration.sh` as your account (no git needed), verifying before it
commits its marker. The image also covers the pre-switch window with a
`/bin/zsh` login shell (the plain base falls back to its default until a
config declares one) and the gc-rooted toolchain pins; the account and
passwordless sudo come from the machine runtime either way.

## c) Build locally

```sh
make build
CONTAINER_IMAGE=local/dotfiles-nixos-cm:latest make launch
```

The Dockerfile takes the repo root as its build context (it clones the
`dotfiles` submodule's pinned SHA into the image's
`~/dotfiles.baked`, a real git repo on a `pinned-<sha7>` branch); the Makefile resolves that context, its
own location, and the pin, so `make build` works from any directory. The image builds with
`container build` straight into the machine runtime's image store: this is a
container machine, so stay on the same tooling - no docker involved (CI
builds the same Dockerfile with `docker buildx` instead - see
[Local (macOS) vs CI builds](../README.md#local-macos-vs-ci-builds)).
Builder networking only works once every
service runs the same CLI version; after a CLI upgrade, restart the whole
stack (`container system stop` / `start`, repointing any stale service
plists under `~/Library/Application Support/com.apple.container/`) if
in-build DNS and TCP fail. This image is single-stage: there is no
throwaway account to purge and no safe build-time
GC (the base's store paths have no registered gcroots until first boot, so
`nix-collect-garbage` at build time would collect the base itself), so a
flatten pass would only duplicate the base for no gain. Machines get a
16G disk.

## How the image works (options a and c)

The design in one line: bake whatever can be baked at build time, and
defer to a one-time first-boot service whatever needs the real user (who
only exists at runtime, and is never whoever ran the build):

- **baked**: the dotfiles clone (`~/dotfiles.baked`, with `~/dotfiles`
  symlinking to it by default), home-manager's generated config, and the
  gc-rooted toolchain pins - all identity-free, kept as a template home at
  `/var/lib/dotfiles-nixos-cm/baked-home` (built as root; nothing under
  `/home`, so the runtime can always provision `/home/<name>`), plus a
  `~/` [Makefile](../template/home/Makefile) and
  the [home README](../template/home/README.md) for switching `~/dotfiles` between
  sources.
- **deferred to first boot**: the runtime creates the real account (your
  host user) on boot; `dotfiles-nixos-cm-firstboot.service` waits for it
  (the runtime writes sudoers last), grafts the template onto the account,
  rewrites the baked paths, creates `~/dotfiles.host` -> your host's
  `/Users/<you>/dotfiles` checkout, then runs the canonical bootstrap
  (`bootstrap/foundation/nixos/switch.sh` + `configuration.sh`) so every
  generated file carries the real identity.
- **one-time**: a verify gate (no baked paths left, the three dotfiles
  paths intact, `nix` on PATH,
  `my_dot_d` rebased) must pass before the marker
  `/var/lib/dotfiles-nixos-cm/firstboot.done` is written; on failure the
  unit retries on the next boot, always from a clean re-graft.

First boot runs template copy + chown, `nixos-rebuild switch`, and
home-manager, so expect minutes rather than seconds; `bin/launch.sh`
waits up to 30 minutes for the marker after creating a machine. Knobs:
image via `CONTAINER_IMAGE`, machine name via `MACHINE` (make) or
`CONTAINER_MACHINE_NAME` (script), default `dotfiles-nixos-cm`;
`DOTFILES_NIXOS_CM_NO_WAIT=1` skips the wait,
`DOTFILES_NIXOS_CM_WAIT_SECS` (default 300) bounds how long the unit waits
for the runtime's sudoers signal. Progress and failures:
`container machine run -n dotfiles-nixos-cm --root journalctl -u dotfiles-nixos-cm-firstboot`

The full detail - unit planting, the profile handover, build-time extras,
and the ubuntu flavor's take on all of this - lives in the shared
[how-it-works.md](../docs/how-it-works.md).

## Clean up

```sh
make delete
```

(Option b's machine goes by its own name, e.g.
`container machine delete my-nixos`.)
