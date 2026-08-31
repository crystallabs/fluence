**Build status**: [![CI](https://github.com/crystallabs/fluence/actions/workflows/ci.yml/badge.svg)](https://github.com/crystallabs/fluence/actions/workflows/ci.yml)
[![Version](https://img.shields.io/github/tag/crystallabs/fluence.svg?maxAge=360)](https://github.com/crystallabs/fluence/releases/latest)
[![License](https://img.shields.io/github/license/crystallabs/fluence.svg)](https://github.com/crystallabs/fluence/blob/master/LICENSE)

# Fluence 0.7.0

Elegant wiki powered by Crystal, with markdown as native format and a WYSIWYG editor.

Content is stored in a Git repository, which is the single source of truth — Fluence keeps no cache or index that can go stale. Two storage modes are supported and auto-detected:

1. **Bare repository** (default for new installations): the data directory is a bare Git repository. Fluence reads from and commits to it directly, without any checkout. External contributions are made with regular Git tooling: `git clone` the data directory (or serve it over SSH/HTTP), edit, commit, and `git push` — pushed changes are visible in the wiki immediately.
1. **Working tree** (used automatically for pre-0.7 data directories): the data directory is a normal checkout. Pages can also be created and edited directly on the filesystem, and such changes are likewise visible immediately. Set the environment variable `FLUENCE_STORAGE=worktree` before first startup to choose this mode for a new installation.

Fluence uses latest versions: Bootstrap 5.3.8, jQuery 3.7.1 slim, EasyMDE 2.20.0, Font Awesome 6.7.2, and highlight.js 11.11.1. All assets are served locally; pages make no requests to external CDNs.

## Installation and Startup

Fluence is implemented in Crystal and you will need a Crystal compiler. Obtain it from https://crystal-lang.org/docs/installation/.

To download and compile Fluence, do:

```bash
git clone https://github.com/crystallabs/fluence
cd fluence
shards
make lint      # builds and runs ameba; should report no failures
crystal spec
make           # or 'make release'
```

Alternatively, build and run it with Docker:

```bash
docker compose up --build
```

The result of the compilation will be one executable file &mdash; bin/fluence.

Run this file and visit [http://localhost:3000/](http://localhost:3000/) in your browser.

To configure Fluence, please do so in `config/options.cr`. After changing the options, you need to rebuild Fluence.

## Example

Here is how it currently looks:

![Fluence Wiki Screenshot](https://raw.githubusercontent.com/crystallabs/fluence/master/docs/screenshot.png)

## Maintenance Tips

When Fluence starts, by default it will create two subdirectories in the current directory:

1. `data/` for actual Wiki pages and their attached media files — a Git repository (bare by default; see storage modes above), with pages under `pages/` and attachments under `media/` in the repository tree
1. `meta/` for metadata, which currently consists of files `users` and `acl`

There are no files or directories required to pre-exist for Fluence to work. The locations can be overridden with the environment variables `FLUENCE_DATADIR` and `FLUENCE_METADIR`.

There is no index or cache: listings, titles, internal-link resolution, and search always operate on the current repository contents, so nothing can go out of sync. (The `meta/pages` and `meta/media` index files written by Fluence <= 0.6 are no longer used and can be deleted.)

Page content is GitHub Flavored Markdown (tables, strikethrough, autolinks, emoji). Links between pages are ordinary markdown links — `[Title](/pages/name)`, or a target relative to the current page such as `[Title](sibling)`. The `[[wikilink]]` syntax of earlier versions is no longer interpreted; to convert existing content once, start Fluence with `FLUENCE_MIGRATE_WIKILINKS=1` — it rewrites all affected pages to standard links, commits them, and exits.



## Current State / Usability

The Fluence Wiki is usable. On-disk format for data won't change so you will be able to upgrade in the future without trouble.

Important things to have in mind currently:

1. The default permissions scheme (which works and can be configured via both `meta/acls` and GUI) by default makes all registered users automatically be admin, and registrations are always open and don't require any confirmation. Therefore, the initial target for deployment and test of Fluence are small/trusted intranets and teams.

Things we have in mind or are working on are listed in [project issues](https://github.com/crystallabs/fluence/issues). Your comments will help us decide on priorities.
