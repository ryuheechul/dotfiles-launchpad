# How the machine images work

Start with the [container-machine README](../README.md) for context first - what a
container machine is compared to a typical container, why this repo uses
one, and the flavors; this page is the detail behind each flavor's
*How it works* sections.

Both flavors ([ubuntu/](../ubuntu/) and [nixos/](../nixos/)) share one design:
bake whatever can be baked at image-build time, and defer everything that
needs the real user to a one-time first-boot service. The real user only
exists inside the running machine - the machine runtime creates it from
your host user on every boot - and is never the identity that ran the
build.

The bake is also a storage decision - see
[storage-cost.md](./storage-cost.md) for the full breakdown (with a
diagram): the image's ~12-13 GB is permanent, while the machine's own
copy is a sparse file that shrinks as you remove content or delete the
machine.

## Common machinery

### The account comes from the runtime, not the image

On every boot the machine runtime provisions an account matching your host
user (name, uid, gid, home `/home/<name>`; your mac home mounts separately
under `/Users/<name>`), and writes `/etc/sudoers.d/<user>` as the very last
step of its user setup (`MachineUserSetup.swift` in
[apple/container](https://github.com/apple/container)). That sudoers file
is the first-boot service's signal that the account, home, and sudo grant
are all in place. Nothing image-side provisions the account itself.

### The image carries a template home, not a live account

The dotfiles bake into a template home outside `/home`:

- ubuntu: `/var/lib/dotfiles-cm/baked-home`, built as a throwaway
  `dotted` account that is purged from the image at the end of the build
- nixos: `/var/lib/dotfiles-nixos-cm/baked-home`, built as root (no
  throwaway account to borrow, and a root bake cannot collide with any
  runtime uid)

Nothing under `/home` exists in either image, so the runtime can always
provision `/home/<name>`; a baked live account holding a uid or username
the host might use would make the runtime refuse to provision.

### Three dotfiles paths in the home

The clone happens at build time (network): the submodule's pin is checked
out on a `pinned-<sha7>` branch. The template home carries the clone
under a stable name, plus two symlinks around it:

| Path | What it is |
| --- | --- |
| `~/dotfiles.baked` | the image's pinned clone (frozen; `pinned-<sha7>` branch) |
| `~/dotfiles` | symlink, defaults to `dotfiles.baked` (relative, so the graft's path rewrite leaves it alone) |
| `~/dotfiles.host` | symlink to the host's own checkout at `/Users/<you>/dotfiles`; created at first boot because the image cannot know the host username |

The grafted `~/` Makefile (`make status` / `point-baked` / `point-host`)
and the `~/` README explaining the table come from the shared
[template/home/](../template/home/), identical for every flavor.

### The source of everything COPYied: `boot/` and `template/`

Per flavor, `boot/` holds its flavor-specific graft files, by
destination:

- `boot/firstboot.sh` -> `/usr/local/sbin/dotfiles-<flavor>-firstboot`;
- `boot/firstboot.service` -> the unit directory (`/etc/systemd/system`
  on ubuntu, `/usr/lib/systemd/system` on nixos).

The common baked-home files come from the shared
[template/home/](../template/home/) in the parent directory. Every file
COPYied into the image lives under one of the two: the flavor's `boot/`
(its first-boot graft files) or the shared `template/home/` (the baked
home).

### First boot grafts the template, then runs the bootstrap once

`dotfiles-<flavor>-firstboot.service` +
`/usr/local/sbin/dotfiles-<flavor>-firstboot`:

1. wait for the runtime's sudoers signal (bounded by `*_WAIT_SECS`,
   default 300);
2. wipe the fresh home, copy the template in, create `~/dotfiles.host`
   (once; an existing one is left alone) and pin `~/dotfiles` back to
   `dotfiles.baked`, `chown` it to the account;
3. rewrite the baked path in text files and absolute symlinks, drop stale
   `.zwc` caches;
4. hand the nix state to the account (see the flavor deltas below);
5. re-run the dotfiles bootstrap as the runtime account so every generated
   file carries the real identity;
6. verify (no baked paths left, the three dotfiles paths intact,
   `nix` on PATH, `my_dot_d` rebased) and
   only then write the marker `/var/lib/dotfiles-<flavor>/firstboot.done`.

The marker short-circuits every later boot. On failure the unit retries on
the next boot, always from a clean re-graft, so partial runs converge.

### Watching and skipping it

First boot runs the bootstrap, so expect minutes rather than seconds;
`bin/launch.sh` waits for the marker after creating a machine (up to 900s
on ubuntu, 1800s on nixos). Progress and failures:

```sh
container machine run -n <machine> --root journalctl -u dotfiles-<flavor>-firstboot
```

Knobs: `DOTFILES_*_NO_WAIT=1` skips the launch wait; `*_WAIT_SECS` bounds
how long the unit waits for the sudoers signal.

## Flavor deltas

### ubuntu (`dotfiles-cm`)

- **login shell**:
  - `/etc/adduser.conf` `DSHELL`, set to `/bin/zsh`; `container machine
    run` starts in zsh with the dotfiles env chain.
  - the image also drops the base's `ubuntu` (uid 1000) account so it can
    never collide with the runtime's.
- **nix is single-user**:
  - the bake's `/nix` tree is handed to the account by `chown`.
  - single-user nix chmods state dirs on every store open, which only the
    owner may do -
    [NixOS/nix#3435](https://github.com/NixOS/nix/issues/3435).
- **bootstrap**:
  - runs `hm.sh switch` + `configuration.sh` - no `nixos-rebuild`, the
    system layer is plain Ubuntu.
- **the bake**:
  - clones the submodule's pin as `~/dotfiles.baked` (real git repo on a
    `pinned-<sha7>` branch) and cleans the Ubuntu skel files
    home-manager would refuse to overwrite.
  - runs `setup.sh` with the same `SKIP_*` guards as the root Dockerfile,
    then `nix-collect-garbage -d`.
  - the template home (~2G) stays in the image as the pristine graft
    source; each machine keeps a second copy as its live home.
- **zshenv quirk**:
  - `/etc/zsh/zshenv` exports `USER`/`LOGNAME`: machine exec passes only
    a hardcoded `PATH` (no image `ENV`), zsh derives `HOME`/`LOGNAME`
    from passwd but never `USER`, and nix's `profile.d/nix.sh` no-ops
    without it - skipping it would drop `~/.nix-profile/bin` from every
    shell.
  - Ubuntu zsh reads `/etc/zsh/zshenv`, not `/etc/zshenv`.

### nixos (`dotfiles-nixos-cm`)

- **login shell**:
  - `/etc/default/useradd` `SHELL`, set to `/bin/zsh` - a stable symlink
    onto a gc-rooted nixpkgs pin, covering the pre-switch window.
  - after first boot's switch the declared config's zsh takes over
    (activation resolves it to its store path, same as on any switched
    host).
- **nix is multi-user**:
  - `/nix` stays root-owned - the daemon needs the store, so there is no
    `chown -R /nix` like the ubuntu flavor.
  - instead the service repoints `.nix-profile` at the account's own
    `/nix/var/nix/profiles/per-user/<name>` and creates the per-user
    profile/gcroot dirs nix never creates on its own for a fresh user
    (the profile lock would fail with "No such file or directory").
- **bootstrap**:
  - runs `bootstrap/foundation/nixos/switch.sh` (`nixos-rebuild switch`,
    then `init-hm` + `hm switch`) followed by `configuration.sh`, with
    the bake's `SKIP_*`/`HINT_*` guards exported so nothing device-only
    or dconf-related runs on a headless machine.
  - the base is built for this: provision documents `nixos-rebuild
    switch` "working out of the box"
    ([provision nixos README](https://github.com/ryuheechul/provision/tree/main/apple/container-machine/nixos)).
  - the split matters here: the image bakes only the home-manager half
    (`nixos-rebuild` needs a booted machine), so the NixOS system itself
    is still built at first boot.
- **the bake**:
  - clones the submodule's pin as `~/dotfiles.baked` (real git repo on a
    `pinned-<sha7>` branch) and `touch ~/.local.zshrc` so
    `configuration.sh` skips its device-only template seed.
  - runs `init-hm.sh` + `hm.sh switch` with the same `SKIP_*` guards as
    the root Dockerfile.
  - build-time quirks (sandboxed-build retries, `keep-going`, TLS: the
    base's nix carries no compiled-in cert path, so the build declares
    `SSL_CERT_FILE` once as a build ARG - visible to every build step,
    absent from the image config - at the canonical
    `/etc/ssl/certs/ca-bundle.crt` path that activation manages at boot,
    plus the bundle symlinked there for tools that use openssl's
    default; purely a BuildKit-bake quirk - the same base built by nix
    itself, in
    [provision's image build](https://github.com/ryuheechul/provision/blob/main/apple/container-machine/nixos/image/default.nix),
    needs none of it because nix's own build plumbing provides the CA
    certs) live as comments next to
    the relevant [Dockerfile](../nixos/Dockerfile) steps.
- **the unit**:
  - planted under `/usr/lib/systemd/system` (with its wanted-by
    symlink): at boot `/etc/systemd/system` is a read-only store symlink
    and `/run/systemd/system` is tmpfs wiped every boot, while `/usr/lib`
    is a real directory activation leaves alone.
  - the unit carries the system-profile `PATH` and the script a
    `/run/current-system/sw/bin/bash` shebang - systemd's service PATH
    stops at `/usr/bin` and has neither bash nor the coreutils the graft
    shells out to.
- **build-time extras** the booted system normally gets from activation:
  - `/usr/bin/env`;
  - a build-only `/etc/passwd` (init-hm runs `whoami`);
  - `/etc/nix/nix.conf` with flakes, no `build-users-group` (the `nixbld`
    group only exists after activation), and `keep-going`.
