FROM ghcr.io/ryuheechul/dotfiles as df

FROM gitpod/workspace-full

## nix
# nix
COPY --from=df --chown=gitpod:gitpod /nix /nix
# symlinks to nix
COPY --from=df --chown=gitpod:gitpod /usr/local /home/gitpod/.nix-profile

## dotfiles
# for actual dot files
COPY --from=df --chown=gitpod:gitpod /home/dotted /home/gitpod
# dot files symlinks to dotfiles
COPY --from=df --chown=gitpod:gitpod /home/dotted/dotfiles /home/gitpod/dotfiles
# this bridges the broken symlinks above
RUN sudo ln -s /home/gitpod /home/dotted

## asdf
# asdf
COPY --from=df --chown=gitpod:gitpod /asdf-home /asdf-home
ENV ASDF_DIR=/asdf-home/.asdf
ENV ASDF_DATA_DIR=/home/gitpod/.asdf

## tmux
# for tmux
ENV SHELL=/usr/local/bin/zsh
