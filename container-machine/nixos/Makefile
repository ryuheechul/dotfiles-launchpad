# Make targets for building and launching the Apple `container` machine image
# in this directory (NixOS flavor of ../). Thin wrappers over `container build`
# and bin/launch.sh; the scripts also work directly from any directory.
#
#   make build             # container build into the machine runtime's image store
#   make launch            # create the machine (or reuse) + wait for first boot
#   make launch-published  # pull the CI-published image, then launch
#   make run               # shell in
#   make stop              # stop the machine
#   make delete            # delete the machine and its state
#
# Local image flow: `make build` then
# `CONTAINER_IMAGE=local/dotfiles-nixos-cm:latest make launch` (plain
# `make launch` pulls the published image; override the machine with
# MACHINE=<name>).

MACHINE ?= dotfiles-nixos-cm
IMAGE ?= local/dotfiles-nixos-cm:latest
PUBLISHED_IMAGE ?= ghcr.io/ryuheechul/dotfiles-launchpad/dotfiles-nixos-cm:latest
HERE := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
# build context stays the repo root: the Dockerfile COPYies the dotfiles
# submodule and its own bin/ + unit files from there
CONTEXT := $(abspath $(HERE)/../..)

# Built with `container build`: same tooling as the machine runtime, so no
# docker involved. Builder networking only works once every service runs the
# same CLI version - after a CLI upgrade, restart the whole stack
# (`container system stop` / `container system start`, repointing any stale
# service plists) if in-build DNS + TCP fail. The -c/-m flags matter: the
# buildkit sandbox defaults to 2 CPU / 2G, which OOMs nix/home-manager steps.
.PHONY: build
build: ## Build the image (context is the repo root)
	container build -c 4 -m 8G -f $(HERE)Dockerfile -t $(IMAGE) $(CONTEXT)

.PHONY: launch
launch: ## Create the machine (or reuse) + wait for first boot
	CONTAINER_MACHINE_NAME=$(MACHINE) $(HERE)bin/launch.sh

# explicit pull so a stale local tag can never shadow the registry
.PHONY: launch-published
launch-published: ## Pull the CI-published image + create/reuse the machine
	container image pull $(PUBLISHED_IMAGE)
	CONTAINER_MACHINE_NAME=$(MACHINE) CONTAINER_IMAGE=$(PUBLISHED_IMAGE) $(HERE)bin/launch.sh

.PHONY: run
run: ## Shell in
	container machine run -n $(MACHINE)

.PHONY: stop
stop: ## Stop the machine
	container machine stop $(MACHINE)

.PHONY: delete
delete: ## Delete the machine and its state
	container machine delete $(MACHINE)
