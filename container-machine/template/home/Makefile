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

point-baked: ## point ~/dotfiles at the image's baked clone
	@test -e $(baked) || { echo "no $(baked) in ~ (image missing its baked clone?)" >&2; exit 1; }
	ln -sfn $(baked) dotfiles
	@echo "~/dotfiles -> $$(readlink dotfiles)"

point-host: ## point ~/dotfiles at the host's repo via ~/dotfiles.host
	@test -e $(host) || { echo "no $(host) in ~ (first boot should have created it)" >&2; exit 1; }
	@echo "~/dotfiles.host -> $$(readlink $(host) 2>/dev/null || echo '(not a symlink)')"
	ln -sfn $(host) dotfiles
	@echo "~/dotfiles -> $$(readlink dotfiles)"

status: ## show where ~/dotfiles and ~/dotfiles.host point
	@printf '~/dotfiles       -> %s\n' "$$(readlink dotfiles 2>/dev/null || echo '(missing)')"
	@printf '~/dotfiles.baked -> %s\n' "$$(test -e $(baked) && echo 'present' || echo '(missing)')"
	@printf '~/dotfiles.host  -> %s\n' "$$(readlink $(host) 2>/dev/null || echo '(missing)')"
