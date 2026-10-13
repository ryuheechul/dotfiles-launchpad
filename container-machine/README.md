# container-machine

[Apple `container`](https://github.com/apple/container)
[machine](https://github.com/apple/container/blob/main/docs/container-machine.md)
images for these dotfiles - the machine cousin of the
[root Docker route](../) and the [Lima route](../#with-lima).

## Container machine primer

A regular container - docker or plain `container` - is a process over an
image's filesystem, started and thrown away. A container machine is meant
to be kept, and differs in three ways:

- **it boots an init system** - the image's designated init path becomes
  PID 1, which allows an init system like systemd to run and manage
  services: a system container, not a single-process one.
- **it persists** - the OS lives on a persistent virtual disk, so
  services, configuration, and installed packages survive stop/start and
  reboots.
- **it follows the host user** - on every boot the machine runtime
  provisions an account matching your host user (name, uid, gid,
  passwordless sudo) and mounts your mac home under `/Users/<name>`,
  instead of shipping whatever user the image baked in.

Machines are a newer approach that combines VM and container - like a VM
you boot a full OS onto a persistent disk; like a container you build it
from an image and drive it with the same CLI. [Lima](https://lima-vm.io),
for one, provided a different way of managing and using a VM - it is
still a real VM, with supports that make it easier than the traditional
way, but without incorporating OCI and the container model.

## Why and how we use it here

**Why.** We use a machine for the VM-like experience - a persistent,
bootable OS with an init system - while keeping container tooling. The
[root README](../) ships the three routes side by side (docker, machine,
Lima).

**How.** Following the host user (see the primer) is why one published
image has to carry this machinery: it must boot for *any* host user, so
nothing identity-specific may live in a real account:

- the dotfiles bake as a template home, never as a live account;
- a first-boot service grafts the template onto whatever account the
  runtime created;
- the machinery is optional - provision the machine yourself and a plain
  base image plus your own clone and bootstrap gets you the same dotfiles
  (option b in the
  [nixos flavor README](./nixos/#b-skip-this-image-use-provisionnixos-cm)).

## Local (macOS) vs CI builds

Both routes produce the same image from the same Dockerfile; only the
builder differs:

- **on macOS (local)**: `container build`, via each flavor's Makefile. The
  image lands in the machine runtime's own image store, ready for
  `make launch`.
- **in CI (GitHub Actions)**: the `container` CLI is not available on any
  hosted runner - GitHub's macOS runners lack the nested virtualization it
  needs
  ([actions/runner-images#13565](https://github.com/actions/runner-images/issues/13565))
  - so the publish workflows build the same Dockerfile with `docker buildx`
  on Linux arm64 runners and push to GHCR; `make launch-published` pulls the
  result back into the `container` image store.

No meaningful difference is expected in the final image: both builders are
BuildKit-based. `container build` drives a BuildKit daemon through
[container-builder-shim](https://github.com/apple/container-builder-shim/blob/main/README.md)
(which is also why removing the local `buildkit` container only forces a
cold rebuild, not a different toolchain), and BuildKit is
[docker's builder backend](https://docs.docker.com/build/buildkit) behind
buildx. Both consume the same Dockerfile and build context (the dotfiles
submodule) and target linux/arm64. The residual drift risk is floating
inputs (the nixpkgs pin, the submodule commit), not the builder choice.

## Flavors

Each supported OS is a flavor directory:

- [`ubuntu/`](./ubuntu/) - `dotfiles-cm`, the shipped flavor: Ubuntu 24.04
  with systemd as `/sbin/init` and dotfiles baked through `setup.sh`
  (single-user nix + home-manager). See its
  [README](./ubuntu/README.md) for the user model, build, and launch flow.
- [`nixos/`](./nixos/) - `dotfiles-nixos-cm`: NixOS flavor on top of
  [ryuheechul/provision](https://github.com/ryuheechul/provision)'s
  published `nixos-cm` base, which also carries a general
  [troubleshoot section](https://github.com/ryuheechul/provision/blob/main/apple/container-machine/README.md#troubleshoot)
  for machine runtime issues. See its
  [README](./nixos/README.md) for the user model, build, and launch flow.

Both flavors share one design - bake what can be baked, defer the real
user to a one-time first boot - with the full breakdown (common machinery
plus per-flavor deltas) in [how-it-works.md](./how-it-works.md).
