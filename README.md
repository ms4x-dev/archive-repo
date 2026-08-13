# archive-repo

Lightweight GitHub repo snapshotting for your shell. Grab the latest code + docs
from any public repo, store it as a single read-only `.tar.gz`, and keep it
up to date with a one-word `update`/`upgrade` — no git history, no clutter, no
duplicate versions piling up.

```sh
archive-repo https://github.com/owner/repo
# Estimated size: ~4 MB
# Proceed? [y/N] y
# -> ~/repo-archives/repo.tar.gz
```

## Why

Sometimes you just want a frozen copy of a repo as it is right now — for offline
reference, in case the original disappears, or so a script/pipeline can pull a
known-good snapshot without depending on GitHub being reachable. Full `git clone
--mirror` gives you the whole commit history and every branch, which is overkill
if all you want is "the current README and source, please." This is that, done
simply, in POSIX shell, with zero dependencies beyond `git`, `curl`, and `tar`.

## Features

- **One command, one archive.** `archive-repo <url>` clones, packages, and stores
  a repo as a read-only tarball.
- **No duplicate versions.** Re-running against an unchanged repo is a no-op.
  When the source updates, the old archive is replaced — you always have exactly
  one current snapshot per repo, not a pile of dated copies.
- **Cheap update checks.** `archive-repo update` reports what's changed upstream
  using a lightweight `git ls-remote` call — no cloning required just to check.
- **Batch mode.** `archive-repos <url1> <url2> ...` checks and totals the size of
  everything before asking for one confirmation, then pulls whatever's new or
  outdated.
- **Read-only by default.** Archives are written `chmod 444` so nothing
  accidentally edits or overwrites your snapshot in place.
- **No dependencies beyond POSIX shell, git, curl, and tar.** Works unmodified on
  Alpine/BusyBox, Debian, macOS, and most Linux distributions.

## Install

```sh
git clone https://github.com/<you>/archive-repo.git
cat archive-repo/archive-repo.sh >> ~/.profile   # or ~/.bashrc, ~/.zshrc
source ~/.profile
```

By default, archives are stored in `~/repo-archives`. To use a different location:

```sh
export ARCHIVE_REPO_DIR=/your/path
```
(add this above the `source` line in your shell profile to make it permanent)

## Usage

```sh
archive-repo <github-url> [branch]     # archive or update a single repo
archive-repo update                    # check all archived repos for updates
archive-repo upgrade                   # re-archive anything outdated
archive-repos <url1> <url2> ...        # archive multiple repos in one batch
```

See [DOCUMENTATION.md](./DOCUMENTATION.md) for full usage details, how version
checking works, configuration, and troubleshooting.

## Requirements

`git`, `curl`, `tar`, and standard POSIX coreutils (`sed`, `grep`, `awk`,
`basename`). No GitHub authentication needed for public repos.

## Limitations

- Snapshots the working tree only — no commit history, no other branches, no
  issues/releases/wiki.
- Public repos only (no auth support yet).
- Change detection is by commit SHA, not content — a force-push to an identical
  tree still triggers a re-download.

Full list in [DOCUMENTATION.md](./DOCUMENTATION.md#known-limitations).

## License

[GNU Affero General Public License v3.0](./LICENSE) — free to use, modify, and
distribute, including commercially, as long as the distributed result (or any
network-accessible service built on it) remains open-source under the same
license. Private, non-distributed use has no obligations attached.
