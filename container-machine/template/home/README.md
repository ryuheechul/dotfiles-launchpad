# ~ (this machine's home)

This is a **container machine** home. The machine was booted from a
prebuilt image that already contains a pinned clone of your dotfiles
(https://github.com/ryuheechul/dotfiles), so
`~/dotfiles` is ready to use from the first shell. This README explains
what is here, how it got here, and how to switch between the two dotfiles
sources you might want.

## The two dotfiles sources

| Path | What it is |
| --- | --- |
| `~/dotfiles` | A symlink — points at whichever source you last chose (defaults to `.baked`). |
| `~/dotfiles.baked` | The **image's clone**, pinned to the exact commit the image was built from, on a `pinned-<sha>` branch. Frozen; use it to see "what the image shipped". |
| `~/dotfiles.host` | A symlink to the **host machine's** dotfiles checkout, bind-mounted into this machine at `/Users/<you>/dotfiles`. Live; use it to work on the same repo you use on the host. |

Switch with the [Makefile](./Makefile) in this directory:

```sh
make status        # where does ~/dotfiles point right now?
make point-baked   # use the image's baked clone
make point-host    # use the host's repo (via ~/dotfiles.host)
```

`~/dotfiles.host` is created once on first boot (it needs your username,
which the image cannot know in advance). If it already exists when the
machine boots, it is left alone so a customized path survives.

## How this machine came to be

1. **Image build** (`container machine` + a Dockerfile): the dotfiles repo
   (https://github.com/ryuheechul/dotfiles) is cloned at the commit
   pinned in the image's build, checked out onto a
   `pinned-<sha>` branch, and a template home is prepared under
   `/var/lib/dotfiles-*/baked-home` (outside `/home`, so it can never
   collide with the account the runtime creates).
2. **First boot**: a systemd unit waits for the machine runtime to create
   your account, then grafts the template home onto it — copying the baked
   clone, rewriting baked paths to your real home, and pointing
   `~/dotfiles` at `~/dotfiles.baked`.
3. **Now**: `~/dotfiles` is a working dotfiles checkout. Flip it to
   `~/dotfiles.host` whenever you would rather edit the host's copy.

The image is **user-agnostic**: no host username or uid is baked into a
live account, so the same image boots on any host. That is also why
`~/dotfiles.host` is resolved at first boot rather than baked.

## longevity

This machine can outlive any single image build. When you rebuild and
relaunch from a newer image, the process above runs again and `~/dotfiles`
is reset to the new image's baked clone — your host repo is untouched
behind `~/dotfiles.host`. Nothing here is destructive; flipping the symlink
back is always enough to return to the previous state.
