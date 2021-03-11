# dotfiles launchpad

This repository is to:
- demonstrate examples of bootstrapping of [dotfiles](https://github.com/ryuheechul/dotfiles)
- test its usability
- package it into a useful form (like a docker image)

## with Docker

### Build
`$ make build`

### Test and play around
`$ make dev`

## with Vagrant

### Test

```
$ vagrant up
$ vagrant ssh
$ zsh

# and enjoy all the packages and configuration that's prepared by `dotfiles`
# such as tmux, nvim with spacevim, lf
```

### Clean up
`$ vagrant destroy`
