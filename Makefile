.PHONY: dev
dev:
	docker compose run --rm dev

.PHONY: tmux
tmux:
	docker compose run --rm dev-tmux

.PHONY: build
build:
	docker compose build

.PHONY: update
update:
	git submodule update --remote dotfiles

