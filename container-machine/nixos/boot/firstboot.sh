#!/run/current-system/sw/bin/bash
# dotfiles-nixos-cm first boot: graft the baked template home onto the account
# the machine runtime created, then run the dotfiles' canonical NixOS bootstrap
# as that account (foundation switch.sh + configuration.sh) so every generated
# store file carries the real home instead of the baked one.
#
# shebang: systemd's service PATH has no bash (bash lives in the system
# profile only, and /usr/bin/env would need bash on PATH to find it), while
# /run/current-system exists by the time any unit starts.
#
# Ordering: the runtime's embedded user setup runs on every boot *after*
# systemd is up and writes /etc/sudoers.d/<user> as its very last step (see
# apple/container MachineUserSetup.swift) - that file is our signal that the
# account, home, and sudo grant are all in place. The provisioning shell
# itself comes from /etc/default/useradd SHELL (the non-ubuntu branch of
# MachineUserSetup.swift), baked in the Dockerfile next to /bin/zsh.
#
# Idempotent: the marker short-circuits re-runs, and a retry always starts
# from a wipe + fresh copy of the pristine template, so partial runs converge.
#
# Differences from the ubuntu flavor: the bake ran as root (no throwaway
# account), so home.nix says root and .nix-profile points at per-user/root;
# nix is multi-user here, so /nix stays root-owned (the daemon needs it) and
# instead of chown -R /nix we hand the account its own per-user profile
# dirs, which nix never creates on its own for a fresh user.
#
# BAKED_HOME's default below; the Dockerfile greps for this exact assignment
# after COPYing the script, so the build fails if the two ever drift.
set -euo pipefail

BAKED_USER="root"
BAKED_HOME="/var/lib/dotfiles-nixos-cm/baked-home"
MARKER="/var/lib/dotfiles-nixos-cm/firstboot.done"
WAIT_SECS="${DOTFILES_NIXOS_CM_WAIT_SECS:-300}"

log() { printf '[dotfiles-nixos-cm-firstboot] %s\n' "$*" >&2; }
fail() { log "verify failed: $*"; exit 1; }

if test -f "$MARKER"; then
  exit 0
fi

# Scans below write NUL-delimited results to $1. Errors surface instead of
# reading as "clean": a find failure aborts (set -e), and grep exit 1 (no
# match, the expected case) is distinguished from >= 2 (read error).
scan_baked_files() {
  local out="$1" list f rc
  list="$(mktemp)"
  find "$home" -xdev -type f -size -32M -print0 > "$list"
  : > "$out"
  while IFS= read -r -d '' f; do
    if grep -qIlZ -- "$BAKED_HOME" "$f"; then
      printf '%s\0' "$f" >> "$out"
    else
      rc=$?
      if test "$rc" -ge 2; then
        rm -f "$list"
        log "grep rc=$rc while scanning $f"
        return "$rc"
      fi
    fi
  done < "$list"
  rm -f "$list"
}

scan_baked_links() {
  find "$home" -xdev -type l -lname "$BAKED_HOME*" -print0 > "$1"
}

# --- 1. wait for the runtime's user setup (sudoers written last) ---
new_user=""
deadline=$((SECONDS + WAIT_SECS))
while test "$SECONDS" -lt "$deadline"; do
  for f in /etc/sudoers.d/*; do
    if test ! -f "$f"; then continue; fi
    if test "$(basename "$f")" = README; then continue; fi
    cand="$(awk 'NR==1 {print $1}' "$f")"
    if test -z "$cand" || test "$cand" = "$BAKED_USER"; then continue; fi
    # the runtime names the file after the user with dots mapped to
    # underscores (MachineUserSetup.swift) - require that so an unrelated
    # passwordless sudoers file can never be mistaken for the provision signal
    if test "$(basename "$f")" != "$(printf '%s' "$cand" | tr '.' '_')"; then continue; fi
    if ! grep -q 'ALL=(ALL) NOPASSWD:ALL' "$f"; then continue; fi
    if getent passwd "$cand" >/dev/null 2>&1; then
      new_user="$cand"
      break
    fi
  done
  if test -n "$new_user"; then break; fi
  sleep 1
done

if test -z "$new_user"; then
  log "timed out after ${WAIT_SECS}s waiting for user setup"
  exit 1
fi

passwd_line="$(getent passwd "$new_user")"
uid="$(cut -d: -f3 <<<"$passwd_line")"
gid="$(cut -d: -f4 <<<"$passwd_line")"
home="$(cut -d: -f6 <<<"$passwd_line")"
log "provisioned user=$new_user uid=$uid gid=$gid home=$home"

if test ! -d "$BAKED_HOME"; then
  log "missing template $BAKED_HOME"
  exit 1
fi
if test -z "$home" || test "$home" = / || test "$home" = "$BAKED_HOME"; then
  log "refusing to graft into '$home'"
  exit 1
fi

# --- 2. replace the fresh home with the template ---
log "grafting template: $BAKED_HOME -> $home"
find "$home" -xdev -mindepth 1 -delete
cp -a "$BAKED_HOME/." "$home/"

# the three dotfiles paths (see template/home/README.md in this flavor):
# ~/dotfiles.baked is the image's pinned clone (came with the copy above),
# ~/dotfiles defaults to it via a relative symlink (also copied; pin the
# default here so a partial run always converges back to it), and
# ~/dotfiles.host is a stable indirection to the host's own checkout. The
# host path cannot be baked - the image cannot know the host username - so
# it is created here, once: an existing symlink is left alone so a
# customized path survives.
if test ! -e "$home/dotfiles.host"; then
  ln -sfn "/Users/$new_user/dotfiles" "$home/dotfiles.host"
  log "created ~/dotfiles.host -> /Users/$new_user/dotfiles"
else
  log "leaving existing ~/dotfiles.host -> $(readlink "$home/dotfiles.host")"
fi
ln -sfn dotfiles.baked "$home/dotfiles"

chown -R "$uid:$gid" "$home"

# compiled zsh caches embed absolute paths from the bake - drop them; zsh
# recompiles from the (clean) sources on demand
find "$home" -xdev -type f -name '*.zwc' -delete

# rewrite the baked path in text files under the home (grep -I: text only,
# binary state such as sqlite caches is left alone)
hits="$(mktemp)"
scan_baked_files "$hits"
while IFS= read -r -d '' f; do
  sed -i "s|$BAKED_HOME|$home|g" "$f"
  log "rewrote $f"
done < "$hits"

# absolute symlinks still pointing into the template home
scan_baked_links "$hits"
while IFS= read -r -d '' link; do
  target="$(readlink "$link")"
  ln -sfn "${target/#$BAKED_HOME/$home}" "$link"
  log "relinked $link"
done < "$hits"
rm -f "$hits"

# home.nix (generated by init-hm.sh at bake time) carries the username as
# well as the path; switch.sh reruns init-hm below and regenerates it too, but
# fix it in place first so a partial retry still has the right identity
hm_conf="$home/.config/home-manager/home.nix"
if test -f "$hm_conf"; then
  sed -i "s|home.username = \"${BAKED_USER}\"|home.username = \"${new_user}\"|" "$hm_conf"
  log "rewrote $hm_conf"
fi

# --- 3. hand the nix profile state to the runtime account ---
# the template's .nix-profile points at per-user/root (the bake ran as
# root) and nix never creates a fresh account's per-user dirs on its own
# (the profile lock fails with "No such file or directory"), so repoint
# the symlink and create both dirs. /nix itself stays root-owned: this is
# multi-user nix and the daemon needs the store, so unlike the ubuntu
# flavor there is no chown -R /nix.
log "repointing profile -> per-user/$new_user"
ln -sfn "/nix/var/nix/profiles/per-user/${new_user}/profile" "$home/.nix-profile"
chown -h "$uid:$gid" "$home/.nix-profile"
mkdir -p "/nix/var/nix/profiles/per-user/${new_user}" \
         "/nix/var/nix/gcroots/per-user/${new_user}"
chown -R "$uid:$gid" \
  "/nix/var/nix/profiles/per-user/${new_user}" \
  "/nix/var/nix/gcroots/per-user/${new_user}"

# --- 4. run the canonical bootstrap as the runtime account ---
# mirrors the NixOS flow in dotfiles/README.md: foundation switch.sh (nixos-rebuild
# first, then init-hm + hm switch - the base is built to be switchable), then the
# platform-agnostic configuration.sh. The exports are inherited by every step and
# keep the bake's guards (nothing device-only, no dconf on a headless machine);
# nested sudo inside switch.sh works because we waited for the runtime's sudoers.
user_steps="$(cat <<'EOS'
set -e
export SKIP_INSTALL_DOOM=1 SKIP_INSTALL_VIM_PLUGINS=1 HINT_FOR_HM_NO_DCONF=1
cd "$HOME/dotfiles"
./bootstrap/foundation/nixos/switch.sh
./bootstrap/configuration.sh
EOS
)"
log "running switch.sh + configuration.sh as $new_user"
sudo -u "$new_user" -H env \
  USER="$new_user" LOGNAME="$new_user" HOME="$home" \
  bash -c "$user_steps"

# switch.sh reruns init-hm.sh, which regenerates home.nix with the import
# path readlink -f-resolved to the baked clone (dotfiles.baked). That would
# freeze home-manager onto the image's copy and make `make point-host` a
# no-op for switch-home. Rebase the import onto the ~/dotfiles flip symlink
# so point-baked/point-host genuinely select the source (behavior-neutral at
# first boot: ~/dotfiles is dotfiles.baked). Same for the dfs-rhc symlink
# configuration.sh just made (it also readlink -f-resolved to the clone).
hm_conf="$home/.config/home-manager/home.nix"
if test -f "$hm_conf"; then
  sed -i 's|/dotfiles\.baked/|/dotfiles/|g' "$hm_conf"
  grep -qF '/dotfiles/nix/home' "$hm_conf" \
    || fail "home.nix import not rebased to ~/dotfiles: $(grep -n 'home-nix-path' "$hm_conf" 2>/dev/null)"
fi
ln -sfn "$home/dotfiles" "$home/.config/dfs-rhc"
test "$(readlink "$home/.config/dfs-rhc")" = "$home/dotfiles" \
  || fail "dfs-rhc not pointing at ~/dotfiles"

# --- 5. verify before committing the marker ---
hits="$(mktemp)"
scan_baked_files "$hits"
if test -s "$hits"; then
  log "baked path still present in:"
  while IFS= read -r -d '' f; do printf '%s\n' "$f" >&2; done < "$hits"
  exit 1
fi
scan_baked_links "$hits"
if test -s "$hits"; then
  log "baked-path symlinks remain:"
  while IFS= read -r -d '' link; do printf '%s\n' "$link" >&2; done < "$hits"
  exit 1
fi
rm -f "$hits"

# the dotfiles layout must have survived the graft whole
readlink "$home/dotfiles" | grep -qx "dotfiles.baked" \
  || fail "~/dotfiles is not dotfiles.baked: $(readlink "$home/dotfiles" 2>/dev/null || echo '<not a symlink>')"
test -e "$home/dotfiles.baked/.git" || fail "baked clone missing .git"
test -e "$home/dotfiles.host" || fail "~/dotfiles.host missing"
test -e "$home/Makefile" || fail "grafted Makefile missing"
test -e "$home/README.md" || fail "grafted README.md missing"

# hm must have regenerated its entrypoints against the runtime home
zshrc_target="$(readlink "$home/.zshrc" 2>/dev/null || true)"
if test -z "$zshrc_target" || test ! -f "$zshrc_target"; then
  fail ".zshrc is not a symlink to an existing path: ${zshrc_target:-<not a symlink>}"
fi
if grep -qF "$BAKED_HOME" "$zshrc_target"; then
  fail "regenerated .zshrc still carries the baked path"
fi
if ! grep -qF "$home" "$zshrc_target"; then
  fail "regenerated .zshrc lacks the runtime home"
fi

# end-to-end probe: the same non-interactive zsh exec that every
# `container machine run <command>` uses
env_out="$(sudo -u "$new_user" -H env USER="$new_user" LOGNAME="$new_user" HOME="$home" \
  zsh -c 'printenv USER my_dot_d XDG_CONFIG_HOME HOME; command -v nix' || true)"
log "env probe: ${env_out//$'\n'/ | }"
if ! grep -qx "$new_user" <<<"$env_out"; then
  fail "USER not visible in a fresh shell"
fi
if ! grep -q '/bin/nix$' <<<"$env_out"; then
  fail "nix not on PATH in a fresh shell"
fi
if grep -qF "$BAKED_HOME" <<<"$env_out"; then
  fail "baked path leaked into the shell env"
fi
if ! grep -qxF "$home/.config/dfs-rhc" <<<"$env_out"; then
  fail "my_dot_d not rebased to the runtime home"
fi

# --- done ---
mkdir -p "$(dirname "$MARKER")"
date -u +%FT%TZ > "$MARKER"
log "first boot complete: $(cat "$MARKER")"
