# dotfiles-cm - a container machine image (non-NixOS): Ubuntu 24.04 with
# systemd as /sbin/init plus a baked template home that the first-boot
# service grafts onto whatever account the machine runtime creates. No host
# username/uid is baked into a live account, so any host can boot it.
#
# Build context is the repo root (this flavor's boot/ + bin/ and the
# shared container-machine/template/home/ get COPYied from there; the
# dotfiles repo is cloned at build time from the submodule pin, not
# COPYied), so the Makefile lives here and passes all
# paths + build args explicitly:
#   make build   (container build, same tooling as the machine runtime)
#
# Multi-stage: every step runs in the `bake` stage, then the finished
# rootfs is copied into the final image as ONE layer. A single-stage build
# would stack the setup.sh layer (~10G of home + nix store) under the
# later GC/purge layers, whose deletions never shrink earlier layers -
# that made the image ~12G. Single-layer lands at ~7G and every machine
# disk derived from it shrinks the same way (~23G -> ~15G).
#
# Layout:
#   /var/lib/dotfiles-cm/baked-home - template home, built as the throwaway
#     'dotted' account (uid 4242) outside /home so it can never collide with
#     the runtime username's /home/<name> (the runtime refuses to provision
#     a user whose home path already exists in the image)
#   /var/lib/dotfiles-cm/baked-home/dotfiles.baked - the image's pinned clone
#     of the dotfiles repo (on a pinned-<sha> branch)
#   /var/lib/dotfiles-cm/baked-home/dotfiles -> dotfiles.baked - the default
#     ~/dotfiles; a relative symlink so the graft's rewrite leaves it alone.
#     ~/dotfiles.host is created at first boot (points at the host's repo).
#   boot/ - this flavor's graft files, by destination: firstboot.sh +
#     firstboot.service go to /usr/local/sbin and /etc/systemd/system.
#     The baked-home files are shared by all flavors and live in
#     container-machine/template/home/ (Makefile, README.md).
#   /usr/local/sbin/dotfiles-cm-firstboot + dotfiles-cm-firstboot.service -
#     waits for the runtime's user setup (it writes sudoers last), swaps the
#     fresh skel home for the template, rewrites the baked path, re-runs
#     home-manager as the runtime account
#
# The systemd-in-container bits follow apple/container's "bring your own
# image" docs
# (https://github.com/apple/container/blob/main/docs/container-machine.md#bring-your-own-image);
# user provisioning itself is done by the machine runtime on boot (edits
# /etc/passwd directly, idempotent), so nothing distro-specific is baked for
# it. The dotfiles recipe mirrors the root Dockerfile (same SKIP_* guards,
# same skel cleanup before hm switch).

FROM ubuntu:24.04 AS bake

ENV container=container

# machine prerequisites: systemd + the tools apple's user setup expects
# (POSIX sh, getent, date, coreutils), sudo so the runtime's passwordless
# grant actually works, git for setup.sh, zsh as the account's login shell
# (container machine run execs the passwd shell; unlike the root Dockerfile,
# there is no ENTRYPOINT here pointing at the nix-profile zsh). adduser is
# not in the ubuntu base image and the machine runtime reads DSHELL from its
# /etc/adduser.conf to pick the provisioning shell (see below). systemd-sysv
# is what creates the /sbin/init symlink the machine boots - on ubuntu noble
# the systemd package alone ships /lib/systemd/systemd but no /sbin/init.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      adduser dbus systemd systemd-sysv openssh-server net-tools iproute2 \
      iputils-ping curl wget vim-tiny man sudo git ca-certificates xz-utils \
      zsh \
    && apt-get clean && rm -rf /var/lib/apt/lists/* && yes | unminimize

# systemd-in-container defaults (apple's example)
RUN >/etc/machine-id && >/var/lib/dbus/machine-id
RUN systemctl set-default multi-user.target
RUN systemctl mask \
      dev-hugepages.mount \
      sys-fs-fuse-connections.mount \
      systemd-update-utmp.service \
      systemd-tmpfiles-setup.service \
      console-getty.service
RUN systemctl disable networkd-dispatcher.service || true

RUN sed -i -e 's/^AcceptEnv LANG LC_\*$/#AcceptEnv LANG LC_*/' /etc/ssh/sshd_config

# container machine exec builds its environment from a hardcoded PATH only
# (no image ENV, no USER/LOGNAME) and zsh fills in HOME/LOGNAME from passwd
# but never USER, while nix's profile.d/nix.sh no-ops unless HOME *and* USER
# are set - which is what made ~/.nix-profile/bin silently missing from every
# machine shell. Append to /etc/zsh/zshenv: ubuntu's zsh is built with
# sysconfdir=/etc/zsh, so it reads that path and ignores /etc/zshenv. It runs
# for all zsh invocations (interactive and zsh -c), before the dotfiles'
# own env chains. Generic: derives the name from passwd at runtime.
RUN printf 'export USER=${USER:-$(id -un)}\nexport LOGNAME=${LOGNAME:-$USER}\n' >> /etc/zsh/zshenv

# the machine runtime takes the provisioning account's login shell from
# /etc/adduser.conf DSHELL on ubuntu/debian images (MachineUserSetup.swift)
# and writes it into passwd at create time - point it at zsh so
# `container machine run` lands in the dotfiles shell (which then sets up
# PATH via its own env chain), not a bare bash. adduser (installed above)
# is what ships the file; noble ships DSHELL commented out and without the
# file the runtime falls back to /bin/bash.
RUN sed -i 's|^#\?DSHELL=.*|DSHELL=/bin/zsh|' /etc/adduser.conf \
    && grep -qx 'DSHELL=/bin/zsh' /etc/adduser.conf

# ---- template home, built as a throwaway account ----
# BAKED_USER/BAKED_HOME must stay in sync with the constants at the top of
# boot/firstboot.sh; the grep assert below fails the build if they drift.
ARG BAKED_USER=dotted
ARG BAKED_UID=4242
ENV BAKED_HOME=/var/lib/dotfiles-cm/baked-home

RUN useradd -m -u ${BAKED_UID} -d ${BAKED_HOME} -s /bin/zsh ${BAKED_USER} \
    && echo "${BAKED_USER} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${BAKED_USER} \
    && chmod 0440 /etc/sudoers.d/${BAKED_USER}

# The guest's ~/dotfiles.baked must be a real git repo (so a running machine
# can `git pull` later) rather than a COPY-ed file dump. Clone the dotfiles
# repo at the submodule's pinned SHA (URL + SHA passed as build args from the
# root Makefile, sourced from .gitmodules + the submodule checkout), then
# check it out and put it on a clearly-named local `pinned-<sha>` branch so
# the pin is obvious and easy to opt out of. blobless clone keeps the fetched
# history small while still leaving a recoverable repo. This runs as root:
# the home dir is created by the first-boot graft, not here. The clone is
# chown'd to the bake account so the repo ends up owned by the same user
# that reads it - no git safe.directory needed. The build needs network for
# this step; ca-certificates is installed above so git can verify TLS.
ARG DOTFILES_URL
ARG DOTFILES_SHA
RUN git clone --filter=blob:none --no-checkout "${DOTFILES_URL}" "${BAKED_HOME}/dotfiles.baked" \
    && git -C "${BAKED_HOME}/dotfiles.baked" checkout "${DOTFILES_SHA}" \
    && git -C "${BAKED_HOME}/dotfiles.baked" switch -c "pinned-$(printf '%s' "${DOTFILES_SHA}" | cut -c1-7)" \
    && test -e "${BAKED_HOME}/dotfiles.baked/.git" \
    && chown -R ${BAKED_UID}:${BAKED_UID} "${BAKED_HOME}/dotfiles.baked"

# default ~/dotfiles is a symlink to the baked clone. Relative target: the
# first-boot graft rewrites only baked-path text and absolute baked-path
# symlinks, so this survives the copy untouched.
RUN ln -s dotfiles.baked ${BAKED_HOME}/dotfiles

# the baked-home files are shared by every flavor (container-machine/
# template/home/), so the ~/ Makefile + README read the same everywhere.
COPY --chown=${BAKED_UID}:${BAKED_UID} container-machine/template/home/Makefile ${BAKED_HOME}/Makefile
COPY --chown=${BAKED_UID}:${BAKED_UID} container-machine/template/home/README.md ${BAKED_HOME}/README.md

USER ${BAKED_USER}
ENV USER=${BAKED_USER}
WORKDIR ${BAKED_HOME}

# Ubuntu's /etc/skel ships default ~/.bashrc and ~/.profile; home-manager
# (programs.bash) manages those and refuses to clobber pre-existing copies.
# The empty ~/.local.zshrc makes configuration.sh skip its device-only
# template seed (same reasoning as the root Dockerfile).
RUN rm -f ${BAKED_HOME}/.bashrc ${BAKED_HOME}/.profile ${BAKED_HOME}/.bash_logout \
    && touch ${BAKED_HOME}/.local.zshrc

# setup.sh runs from the baked clone; through the symlink it reads as
# ~/dotfiles, which is the same layout the first-boot re-run uses.
RUN SKIP_INSTALL_DOOM=1 SKIP_INSTALL_VIM_PLUGINS=1 HINT_FOR_HM_NO_DCONF=1 \
      ${BAKED_HOME}/dotfiles/setup.sh

# setup.sh's init-hm.sh pins home.nix's import to the resolved clone
# (dotfiles.baked) via readlink -f, which would freeze home-manager onto
# the image's copy and make `make point-host` a no-op for switch-home.
# Rebase it onto the ~/dotfiles flip symlink so point-baked/point-host
# genuinely select the source. The baked clone is what ~/dotfiles points
# at by default, so this is behavior-neutral until a flip happens.
RUN sed -i 's|/dotfiles\.baked/|/dotfiles/|g' ${BAKED_HOME}/.config/home-manager/home.nix \
    && grep -qF '/dotfiles/nix/home' ${BAKED_HOME}/.config/home-manager/home.nix \
    && ! grep -q 'dotfiles\.baked' ${BAKED_HOME}/.config/home-manager/home.nix

# drop the build-only store paths; the home-manager generation and
# ~/.nix-profile are gcroots (registered under /nix/var/nix/gcroots into the
# template home), so the runtime closure survives
RUN . ${BAKED_HOME}/.nix-profile/etc/profile.d/nix.sh \
    && nix-collect-garbage -d

# ---- first-boot graft service (root: it manages other accounts) ----
USER root
COPY container-machine/ubuntu/boot/firstboot.service /etc/systemd/system/dotfiles-cm-firstboot.service
COPY container-machine/ubuntu/boot/firstboot.sh /usr/local/sbin/dotfiles-cm-firstboot
RUN chmod 0755 /usr/local/sbin/dotfiles-cm-firstboot \
    && grep -qF 'BAKED_HOME="/var/lib/dotfiles-cm/baked-home"' /usr/local/sbin/dotfiles-cm-firstboot \
    && systemctl enable dotfiles-cm-firstboot.service

# ---- purge the throwaway identity (user-agnostic hand-off) ----
# The machine runtime fails loudly if a *different* account in the image
# already holds the host's uid or username, and refuses when anything exists
# at the target home path. Drop 'dotted' (home itself stays as the template),
# the base image's ubuntu account (uid 1000 - would clash with linux hosts),
# and assert no other uid 1000..65533 account remains (65534 = nobody).
#
# /nix was created by the throwaway uid but gets used by whoever the runtime
# creates: single-user nix needs to write its db, add store paths, and
# register gcroots. Share write access on everything - this is a personal
# single-user machine with no daemon and no trust boundary between accounts.
RUN set -eux; \
    userdel "${BAKED_USER}"; \
    rm -f /etc/sudoers.d/"${BAKED_USER}"; \
    if getent passwd ubuntu >/dev/null; then userdel -r ubuntu; fi; \
    leftovers="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}')"; \
    test -z "${leftovers}"; \
    test -z "$(ls -A /home 2>/dev/null || true)"; \
    test -d "${BAKED_HOME}"; \
    test -e "${BAKED_HOME}/dotfiles.baked/.git"; \
    test -L "${BAKED_HOME}/dotfiles"; \
    chmod -R a+rwX /nix

# ---- final: the whole purged rootfs as a single layer ----
FROM ubuntu:24.04
COPY --from=bake / /
