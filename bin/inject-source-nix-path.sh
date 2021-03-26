#!/usr/bin/env sh

echo 'if [ -e /usr/local/etc/profile.d/nix.sh ]; then . /usr/local/etc/profile.d/nix.sh; fi' >> ~/.zshrc
echo 'if [ -e ~/.nix-profile/etc/profile.d/nix.sh ]; then . ~/.nix-profile/etc/profile.d/nix.sh; fi' >> ~/.zshrc
