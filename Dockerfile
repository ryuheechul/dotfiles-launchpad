# heavily inspired by https://jpetazzo.github.io/2020/04/01/quest-minimal-docker-images-part-3/

##########  nix ###########

FROM nixos/nix

RUN mkdir -p /output/store

COPY dotfiles/nix/bin/channels.sh /nix-bootstrap/bin/channels.sh
COPY dotfiles/nix/darwin /nix-bootstrap/darwin
COPY dotfiles/nix/pkgs.nix /nix-bootstrap/pkgs.nix

RUN nix-shell -p bash --command '/nix-bootstrap/bin/channels.sh'; nix-env -iA nixpkgs.nix

# to allow nix binary in a /output/profile too
RUN nix-env --profile /output/profile -iA nixpkgs.nix

RUN nix-env --profile /output/profile -f /nix-bootstrap/pkgs.nix -i

RUN cp -va $(nix-store -qR /output/profile) /output/store

########## main ###########

FROM alpine:3.12.4

RUN addgroup -S dotted && adduser -S dotted -G dotted
RUN mkdir -p /asdf-home && chown dotted /asdf-home

RUN mkdir -p /nix && chown dotted:dotted /nix

USER dotted
WORKDIR /home/dotted

ENV ASDF_DIR=/asdf-home/.asdf
ENV ASDF_DATA_DIR=/home/dotted/.asdf

COPY --from=0 --chown=dotted:dotted /output/store    /nix/store
COPY --from=0 --chown=dotted:dotted /output/profile/ /usr/local/

COPY --chown=dotted:dotted dotfiles /home/dotted/dotfiles

RUN ~/dotfiles/bootstrap/configuration.sh && rm -rf ~/.cache

ENTRYPOINT ["/usr/local/bin/zsh"]
