# dotfiles-nixos-cm - a container machine image (NixOS): the provision
# container-machine base (systemd as init, multi-user nix) plus a baked
# template home that the first-boot service grafts onto whatever account
# the machine runtime creates. No host username/uid is baked into a live
# account, so any host can boot it.
#
# Build context is the repo root (this flavor's bin/ + unit files get
# COPYied from there; the dotfiles repo is cloned at build time from the
# submodule pin, not COPYied), so the Makefile lives here and passes all
# paths + build args explicitly:
#   make build   (container build, same tooling as the machine runtime)
#
# Single-stage on purpose: unlike the ubuntu flavor there is no throwaway
# account to purge and no safe build-time GC (the base image's store paths
# have no registered gcroots until first boot, so nix-collect-garbage at
# build time collects the base itself - observed: 670 system paths gone),
# so a flatten pass would only duplicate the base for no gain.
#
# Layout:
#   /var/lib/dotfiles-nixos-cm/baked-home - template home, built as root
#     (nixos has no throwaway useradd account to borrow and a root bake
#     cannot collide with any runtime uid); outside /home so it can never
#     collide with the runtime username's /home/<name> (the runtime refuses
#     to provision a user whose home path already exists in the image)
#   /usr/lib/systemd/system/dotfiles-nixos-cm-firstboot.{service} + wants
#     symlink - waits for the runtime's user setup (it writes sudoers
#     last), swaps the fresh home for the template, rewrites the baked
#     path, runs the canonical bootstrap (foundation switch.sh +
#     configuration.sh) as the runtime account.
#     /usr/lib/systemd/system is a systemd load root that NixOS activation
#     leaves alone (unlike /etc/systemd/system, which is a read-only store
#     symlink at boot).
#
# The base image already boots systemd as init in machines; user
# provisioning itself is done by the machine runtime on boot (edits
# /etc/passwd directly, idempotent), so nothing distro-specific is baked
# for it. The dotfiles recipe mirrors the root Dockerfile (same SKIP_*
# guards).

FROM ghcr.io/ryuheechul/provision/nixos-cm:latest

# build-time environment the booted system normally gets from activation:
# - tmpfiles dirs (/tmp, /root) that a build RUN never gets
# - /etc/nix/nix.conf: flakes for the bake; no build-users group (nixbld
#   only exists after activation, so root builds directly); keep-going so
#   the unsandboxed purity check (user/mount namespaces are blocked in
#   buildkit, so nix cannot sandbox) only costs retries instead of the
#   whole switch - see the retry loop below
# - minimal passwd/group for build-time getpwuid (init-hm runs whoami);
#   activation regenerates /etc/passwd on first boot anyway
# - /usr/bin/env, normally created at boot by environment.usrbinenv, for
#   #!/usr/bin/env scripts (the dotfiles scripts)
RUN mkdir -p /tmp /root /etc/nix /etc/default /usr/bin && chmod 1777 /tmp \
    && printf 'extra-experimental-features = nix-command flakes\nbuild-users-group =\nsandbox = true\nkeep-going = true\n' >> /etc/nix/nix.conf \
    && printf 'root:x:0:0:root:/root:/bin/sh\n' > /etc/passwd \
    && printf 'root:x:0:\n' > /etc/group \
    && ln -sfn "$(ls /nix/store/*-coreutils-*/bin/env | head -1)" /usr/bin/env \
    && whoami

# login shell: MachineUserSetup reads SHELL from /etc/default/useradd on
# non-ubuntu images (fallback would be /bin/sh -> the base's
# container-machine-shell), so bake zsh from the same pin the provision
# builders use, expose it at a stable path, gc-root it so a later root GC
# cannot collect it, and point useradd at it. zsh has several outputs -
# keep the one that actually ships bin/zsh. SSL_CERT_FILE is only needed
# at build time: /etc/ssl is materialized by activation at boot.
RUN export SSL_CERT_FILE="$(ls /nix/store/*-nss-cacert-*/etc/ssl/certs/ca-bundle.crt | head -1)" \
    && nix build --no-link 'github:NixOS/nixpkgs/nixos-26.05#zsh' --print-out-paths \
      | while read -r p; do test -x "$p/bin/zsh" && echo "$p" && break; done > /tmp/zshpath \
    && test -n "$(cat /tmp/zshpath)" \
    && mkdir -p /var/lib/dotfiles-nixos-cm \
    && ln -sfn "$(cat /tmp/zshpath)/bin/zsh" /bin/zsh \
    && nix-store --add-root /var/lib/dotfiles-nixos-cm/zsh.gcroot -r "$(cat /tmp/zshpath)" \
    && printf 'SHELL=/bin/zsh\n' > /etc/default/useradd \
    && /bin/zsh --version

# what apple's MachineUserSetup derives for non-ubuntu images
RUN unset SHELL; . /etc/default/useradd; test "$SHELL" = /bin/zsh

# gcroot the cacert store path the same way (SSL_CERT_FILE above is a
# store path; roots keep both alive under a later runtime GC)
RUN export SSL_CERT_FILE="$(ls /nix/store/*-nss-cacert-*/etc/ssl/certs/ca-bundle.crt | head -1)" \
    && nix-store --add-root /var/lib/dotfiles-nixos-cm/cacert.gcroot -r "${SSL_CERT_FILE%/etc/ssl/certs/ca-bundle.crt}"

# ---- template home, built as root ----
# The first-boot script carries the same value as its default; the build
# asserts the two match right after COPYing it (see below).
ENV BAKED_HOME=/var/lib/dotfiles-nixos-cm/baked-home

RUN mkdir -p ${BAKED_HOME} && touch ${BAKED_HOME}/.local.zshrc

# The guest's ~/dotfiles must be a real git repo (so a running machine can
# `git pull` later) rather than a COPY-ed file dump. Clone the dotfiles repo
# at the submodule's pinned SHA (URL + SHA passed as build args from the root
# Makefile, sourced from .gitmodules + the submodule checkout), then check it
# out and put it on a clearly-named local `pinned-<sha>` branch so the pin is
# obvious and easy to opt out of. blobless clone keeps the fetched history
# small while still leaving a recoverable repo. The whole bake runs as root,
# which owns the clone, so no git ownership fixups are needed. The build
# needs network for this step (it already does for nix).
ARG DOTFILES_URL
ARG DOTFILES_SHA
RUN export SSL_CERT_FILE="$(ls /nix/store/*-nss-cacert-*/etc/ssl/certs/ca-bundle.crt | head -1)" \
    && git clone --filter=blob:none --no-checkout "${DOTFILES_URL}" "${BAKED_HOME}/dotfiles" \
    && git -C "${BAKED_HOME}/dotfiles" checkout "${DOTFILES_SHA}" \
    && git -C "${BAKED_HOME}/dotfiles" switch -c "pinned-$(printf '%s' "${DOTFILES_SHA}" | cut -c1-7)"

# mirror the home-manager half of bootstrap/foundation/nixos/switch.sh
# (init + switch), with the same SKIP_* guards the ubuntu flavor bakes
# with; nixos-rebuild needs a booted machine and runs at first boot, never
# here. nix already exists in this image (the base ships multi-user nix),
# so the install step is skipped entirely. Some hm build does mkdir $HOME
# (/homeless-shelter); with sandboxing blocked that makes the next build
# refuse to start (purity check), so retry after cleanup - realized builds
# stay in the store and the switch converges (observed: 7 attempts).
# The generated home.nix must carry the baked user (root); the first-boot
# script rewrites it to the runtime account.
RUN export SSL_CERT_FILE="$(ls /nix/store/*-nss-cacert-*/etc/ssl/certs/ca-bundle.crt | head -1)" \
    && export HOME="${BAKED_HOME}" USER=root \
    && cd "${BAKED_HOME}/dotfiles" \
    && SKIP_INSTALL_DOOM=1 SKIP_INSTALL_VIM_PLUGINS=1 HINT_FOR_HM_NO_DCONF=1 ./nix/bin/init-hm.sh \
    && ok=0 && i=1 \
    && while test "$i" -le 80; do \
         rm -rf /homeless-shelter; \
         if SKIP_INSTALL_DOOM=1 SKIP_INSTALL_VIM_PLUGINS=1 HINT_FOR_HM_NO_DCONF=1 ./nix/bin/hm.sh switch > /tmp/hm-attempt.log 2>&1; then \
           ok=1; echo "hm switch converged on attempt $i"; break; \
         fi; \
         echo "attempt $i failed: $(tail -1 /tmp/hm-attempt.log)"; \
         i=$((i + 1)); \
       done \
    && rm -rf /homeless-shelter \
    && if test "$ok" != 1; then \
         echo "hm switch never converged; last attempt:" >&2; tail -40 /tmp/hm-attempt.log >&2; exit 1; \
       fi \
    && test -e "${BAKED_HOME}/.nix-profile/bin/home-manager" \
    && grep -q 'home.username = "root"' "${BAKED_HOME}/.config/home-manager/home.nix"

# ---- first-boot graft service (root: it manages other accounts) ----
# systemd's unit load roots at boot are /etc/systemd/system (read-only
# store symlink), /run/systemd/system (tmpfs, wiped per boot) and
# /usr/lib/systemd/system (real dir here, untouched by activation), so
# plant the unit + its wanted-by symlink under /usr/lib. `systemctl
# enable` cannot be used: no systemd runs at build time and the /etc
# location it would write is the read-only one at boot.
COPY container-machine/nixos/dotfiles-nixos-cm-firstboot.service /usr/lib/systemd/system/dotfiles-nixos-cm-firstboot.service
COPY container-machine/nixos/bin/dotfiles-nixos-cm-firstboot.sh /usr/local/sbin/dotfiles-nixos-cm-firstboot
RUN chmod 0755 /usr/local/sbin/dotfiles-nixos-cm-firstboot \
    && grep -qF "BAKED_HOME=\"${BAKED_HOME}\"" /usr/local/sbin/dotfiles-nixos-cm-firstboot \
    && mkdir -p /usr/lib/systemd/system/multi-user.target.wants \
    && ln -s /usr/lib/systemd/system/dotfiles-nixos-cm-firstboot.service \
       /usr/lib/systemd/system/multi-user.target.wants/dotfiles-nixos-cm-firstboot.service

# ---- assert the user-agnostic hand-off ----
# The machine runtime refuses when anything exists at the target home path
# and fails loudly if an account in the image already holds the host's uid
# or username. The bake ran as root (system uid, fine) and never touched
# /home; assert /home is absent or empty. The shims smoke check guards the
# /bin tools the graft shells out to (cut/grep/id/chown) and the login
# shell chain.
RUN test -z "$(ls -A /home 2>/dev/null || true)" \
    && test -d "${BAKED_HOME}" \
    && /bin/sh -c true \
    && /usr/bin/env true \
    && test -x /bin/zsh \
    && for f in /bin/chown /bin/cut /bin/grep /bin/id; do "$f" --version >/dev/null; done \
    && whoami \
    && nix --version
