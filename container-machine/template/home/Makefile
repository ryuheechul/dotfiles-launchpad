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

# Repointing ~/dotfiles moves everything that reads the source, because both
# ~/.config/dfs-rhc and home.nix's import point through the ~/dotfiles symlink
# (not at the resolved clone). So the flip is all-at-once - the only remaining
# step is to re-apply, so remind the user to run switch-home / switch-nix.
point_note = printf 'note: ~/dotfiles, ~/.config/dfs-rhc and home.nix now all point at the new source.\nnote: run switch-home (or switch-nix) to rebuild from it.\n'

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
