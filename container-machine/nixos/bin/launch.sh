#!/usr/bin/env bash
# Create the Apple container machine from the published dotfiles-nixos-cm
# image - NixOS + systemd with a baked template home grafted by the
# first-boot service (see Dockerfile here).
#
# Usage: bin/launch.sh
# Env:   CONTAINER_MACHINE_NAME (default "dotfiles-nixos-cm")
#        CONTAINER_IMAGE        (default the published latest tag)
set -euo pipefail

name="${CONTAINER_MACHINE_NAME:-dotfiles-nixos-cm}"
# published by .github/workflows/dotfiles-nixos-cm-publish.yml (dispatch-only);
# tags: latest and sha-<short>. Override to try a locally built image, e.g.
# CONTAINER_IMAGE=local/dotfiles-nixos-cm:latest
image="${CONTAINER_IMAGE:-ghcr.io/ryuheechul/dotfiles-launchpad/dotfiles-nixos-cm:latest}"

command -v container >/dev/null || { echo "Apple 'container' CLI not found" >&2; exit 1; }

# reuse the machine if it already exists; otherwise create it. user
# provisioning happens automatically on boot (runtime-edited /etc/passwd);
# a first-boot unit then grafts the template home (see
# bin/dotfiles-nixos-cm-firstboot.sh) - creation returns before that
# finishes.
created=0
if container machine list 2>/dev/null | grep -q "^$name[[:space:]]"; then
  echo "machine '$name' already exists; leaving it as-is"
else
  container machine create "$image" --name "$name" --cpus 4 --memory 8G
  created=1
fi

marker_test() {
  container machine run -n "$name" --root \
    test -f /var/lib/dotfiles-nixos-cm/firstboot.done 2>/dev/null
}

# wait for the first-boot graft unless asked not to (DOTFILES_NIXOS_CM_NO_WAIT=1)
if test "${DOTFILES_NIXOS_CM_NO_WAIT:-0}" != 1; then
  if test "$created" -eq 1; then
    echo "waiting for first-boot provisioning (template graft + nixos-rebuild + hm switch) ..."
    # first boot runs nixos-rebuild + home-manager; keep generous headroom
    # for a cold system build in the machine
    deadline=$((SECONDS + 1800))
    until marker_test; do
      if test "$SECONDS" -ge "$deadline"; then
        echo "timed out waiting for the first-boot marker; inspect with:" >&2
        printf '  container machine run -n %q --root journalctl -u dotfiles-nixos-cm-firstboot\n' "$name" >&2
        echo "  (a reboot retries the first-boot unit)" >&2
        exit 1
      fi
      sleep 5
    done
    echo "first-boot provisioning done"
  elif ! marker_test; then
    echo "note: no first-boot marker - the image may predate user-agnostic" >&2
    echo "      support (recreate the machine from a fresh image)" >&2
  fi
fi

echo
echo "machine '$name' ready; shell in:"
printf '  container machine run -n %q\n' "$name"
