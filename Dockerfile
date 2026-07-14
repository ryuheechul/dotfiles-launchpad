# Two stages:
#   builder - run dotfiles' own setup.sh (single-user nix + home-manager, the
#             same path GitHub Codespaces uses), then garbage-collect the
#             build-time deps out of /nix/store.
#   final   - copy only the GC'd store + the bootstrapped HOME into a fresh
#             image, dropping the ubuntu build packages and the fat
#             intermediate layers.
# The copy is what actually shrinks the image: a GC in a single stage wouldn't,
# because earlier layers keep the deleted paths. (This is the modern take on
# the old nixos/nix -> alpine store-copy build, which had rotted -
# nix/bin/channels.sh, a SpaceVim cache-clean, and asdf env vars are all gone
# from dotfiles now.)

# ---------- builder ----------
FROM ubuntu:24.04 AS builder

# deps the nix installer needs (curl + xz), plus git/sudo/ca-certificates
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl xz-utils git ca-certificates sudo \
    && rm -rf /var/lib/apt/lists/*

# single-user nix installs under a normal user's home; give it passwordless
# sudo so the installer can create /nix
RUN useradd -m -s /bin/bash dotted \
    && echo 'dotted ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dotted \
    && chmod 0440 /etc/sudoers.d/dotted
USER dotted
ENV USER=dotted
WORKDIR /home/dotted

COPY --chown=dotted:dotted dotfiles /home/dotted/dotfiles

# Ubuntu's /etc/skel ships default ~/.bashrc and ~/.profile; home-manager
# (programs.bash) manages those and refuses to clobber pre-existing copies, so
# drop the skel ones before setup.sh's `hm switch` runs.
#
# also pre-create an empty ~/.local.zshrc: configuration.sh seeds it from
# bootstrap/local.zshrc.template only when absent, and that template carries
# device-provisioning toggles (MY_NIX_EXTRA_DEVENV, ...) a minimal image
# shouldn't bake. An empty file makes the seed skip.
RUN rm -f /home/dotted/.bashrc /home/dotted/.profile /home/dotted/.bash_logout \
    && touch /home/dotted/.local.zshrc

# setup.sh: install single-user nix, install + switch home-manager, then run
# configuration.sh.
# - SKIP_* keep this throwaway image lean: doom's installer needs an interactive
#   terminal (absent in a build) and nvim's plugin sync is slow; neither is
#   essential for launchpad's purpose.
# - HINT_FOR_HM_NO_DCONF drops dconf (GNOME desktop settings), whose
#   home-manager activation needs a dbus session that a headless container
#   doesn't have.
RUN SKIP_INSTALL_DOOM=1 SKIP_INSTALL_VIM_PLUGINS=1 HINT_FOR_HM_NO_DCONF=1 \
      /home/dotted/dotfiles/setup.sh

# collect the build-only store paths (compilers, sources, -dev outputs); the
# home-manager generation and ~/.nix-profile are gcroots, so the runtime
# closure survives. (`nix-store --optimise` is skipped: hardlink dedup fails
# with EXDEV across the build's overlay filesystem, and the copy below drops
# the fat regardless.)
RUN . /home/dotted/.nix-profile/etc/profile.d/nix.sh \
    && nix-collect-garbage -d

# ---------- final ----------
FROM ubuntu:24.04

RUN useradd -m -s /bin/bash dotted
USER dotted
ENV USER=dotted
WORKDIR /home/dotted

# the slimmed store and the fully bootstrapped HOME (dotfiles symlinks, zinit,
# tpm, mise state) - nothing needs re-running in this stage
COPY --from=builder --chown=dotted:dotted /nix /nix
COPY --from=builder --chown=dotted:dotted /home/dotted /home/dotted

ENV SHELL=/home/dotted/.nix-profile/bin/zsh
ENTRYPOINT ["/home/dotted/.nix-profile/bin/zsh"]
