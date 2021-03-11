# heavily inspired by https://jpetazzo.github.io/2020/04/01/quest-minimal-docker-images-part-3/

##########  nix ###########

FROM nixos/nix
RUN nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs
RUN nix-channel --update; nix-env -iA nixpkgs.nix

RUN mkdir -p /output/store

COPY dotfiles/nix/pkgs.nix /nix-input/pkgs.nix

RUN nix-env --profile /output/profile -f /nix-input/pkgs.nix -i

RUN cp -va $(nix-store -qR /output/profile) /output/store

########## main ###########

FROM alpine:3.12.4

RUN addgroup -S dotted && adduser -S dotted -G dotted
RUN mkdir -p /asdf-home && chown dotted /asdf-home
USER dotted
WORKDIR /home/dotted

ENV ASDF_DIR=/asdf-home/.asdf
ENV ASDF_DATA_DIR=/home/dotted/.asdf

COPY --from=0 /output/store    /nix/store
COPY --from=0 /output/profile/ /usr/local/

COPY --chown=dotted:dotted dotfiles /home/dotted/dotfiles

RUN ~/dotfiles/bootstrap/configuration.sh

ENTRYPOINT ["/usr/local/bin/zsh"]
