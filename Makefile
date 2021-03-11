.PHONY: dev
dev: build
	docker-compose run dev

.PHONY: build
build:
	docker-compose build
