.PHONY: dev
dev:
	docker-compose run dev

.PHONY: tmux
tmux:
	docker-compose run dev-tmux

.PHONY: build
build:
	docker-compose build
