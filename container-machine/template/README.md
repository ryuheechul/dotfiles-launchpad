# template/

Shared files COPYied into every flavor's image. Unlike the flavor-specific
graft files (which live in each flavor's [boot/](../ubuntu/boot/)), these
are identical no matter which flavor is being baked.

## What's here

- [home/](./home/) - the baked home. Its `Makefile` and `README.md` land in
  the `~/` of the image, so every machine gets the same home regardless of
  flavor.

## How it's used

`home/` is a **template home**, not a live account: it is baked outside
`/home` as root, then on first boot it is grafted (copied + chowned) onto
whatever account the machine runtime creates from your host user. See
[how-it-works.md](../docs/how-it-works.md) for the full flow and
[storage-cost.md](../docs/storage-cost.md) for what that copy costs on disk.

If a file belongs to the baked home and reads the same on every flavor, put
it here. Flavor-only first-boot scripts and units belong in that flavor's
`boot/` directory instead.
