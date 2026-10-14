# Switch ~/dotfiles between the image's baked clone and the host's repo.
#
#   make point-baked   # ~/dotfiles -> ~/dotfiles.baked  (image's pinned clone)
#   make point-host    # ~/dotfiles -> ~/dotfiles.host   (host's /Users/<you>/dotfiles)
#   make status        # show where ~/dotfiles and ~/dotfiles.host point
#
# The machine image bakes a pinned clone of the dotfiles repo at
# ~/dotfiles.baked (on a pinned-<sha> branch) and grafts it here on first
# boot. ~/dotfiles.host is a stable indirection to the host machine's own
# dotfiles checkout (bind-mounted at /Users/<you>/dotfiles), so you can flip
# between "what the image shipped" and "what I already have on the host"
# without rewriting the host path.

.PHONY: point-baked point-host status

baked := dotfiles.baked
host  := dotfiles.host

# Repointing ~/dotfiles only flips the symlink. The source the tools actually
# read (~/.config/dfs-rhc) is set separately by bootstrap/configuration.sh,
# and nothing is re-applied until switch-home / switch-nix runs - so remind
# the user the flip is partial until both are done.
point_note = printf 'note: only ~/dotfiles moved.\nnote: ~/.config/dfs-rhc is unchanged (set via bootstrap/configuration.sh); run switch-home (or switch-nix) for the new source to fully take effect.\n'

point-baked: ## point ~/dotfiles at the image's baked clone
	@test -e $(baked) || { echo "no $(baked) in ~ (image missing its baked clone?)" >&2; exit 1; }
	ln -sfn $(baked) dotfiles
	@echo "~/dotfiles -> $$(readlink dotfiles)"
	@$(point_note)

point-host: ## point ~/dotfiles at the host's repo via ~/dotfiles.host
	@test -e $(host) || { echo "no $(host) in ~ (first boot should have created it)" >&2; exit 1; }
	@echo "~/dotfiles.host -> $$(readlink $(host) 2>/dev/null || echo '(not a symlink)')"
	ln -sfn $(host) dotfiles
	@echo "~/dotfiles -> $$(readlink dotfiles)"
	@$(point_note)

status: ## show where ~/dotfiles, ~/dotfiles.host and ~/.config/dfs-rhc point
	@printf '~/dotfiles       -> %s\n' "$$(readlink dotfiles 2>/dev/null || echo '(missing)')"
	@printf '~/dotfiles.baked -> %s\n' "$$(test -e $(baked) && echo 'present' || echo '(missing)')"
	@printf '~/dotfiles.host  -> %s\n' "$$(readlink $(host) 2>/dev/null || echo '(missing)')"
	@printf '~/.config/dfs-rhc -> %s\n' "$$(readlink ~/.config/dfs-rhc 2>/dev/null || echo '(missing)')"
