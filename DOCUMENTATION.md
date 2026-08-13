# archive-repo — Documentation

A pair of POSIX shell functions for taking lightweight, dependency-free snapshots
of GitHub repositories: latest code + docs, no git history, stored as a single
read-only `.tar.gz` per repo that's automatically replaced when the source updates.

This document covers installation, usage, internal behavior, and troubleshooting.
For a quick pitch and copy-paste quick start, see `README.md`.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Concepts](#concepts)
4. [Usage](#usage)
5. [File Layout](#file-layout)
6. [How Version Checking Works](#how-version-checking-works)
7. [Configuration](#configuration)
8. [Troubleshooting](#troubleshooting)
9. [Known Limitations](#known-limitations)
10. [Extending the Script](#extending-the-script)

---

## Requirements

| Dependency | Notes |
|---|---|
| POSIX shell | Written for `ash`/`dash`/`bash`. No bashisms — works unmodified on Alpine, Debian, macOS, BusyBox environments. |
| `git` | Used for `clone` and `ls-remote`. |
| `curl` | Used to query the GitHub API for size estimates. |
| `tar` | Used to package the archive. |
| `sed`, `grep`, `awk`, `basename` | Standard coreutils, present on virtually all Linux/BSD systems. |

No GitHub authentication is required for public repos. Unauthenticated API requests
are rate-limited by GitHub to 60/hour per IP — see [Limitations](#known-limitations).

---

## Installation

1. Copy the function definitions (found in `archive-repo.sh` in this repo) into your
   shell's startup file:

   ```sh
   cat archive-repo.sh >> ~/.profile      # or ~/.bashrc, ~/.zshrc, etc.
   source ~/.profile
   ```

2. Set a storage directory. By default the functions write to `/tank/git` — a path
   specific to the original author's ZFS layout. **You will almost certainly want to
   change this.** See [Configuration](#configuration).

3. Confirm it loaded:

   ```sh
   archive-repo
   # usage: archive-repo <github-url> [branch] | archive-repo update | archive-repo upgrade
   ```

---

## Concepts

**Snapshot, not mirror.** Each archive is a shallow clone (`git clone --depth 1`) of
one branch at one point in time, with `.git` stripped before packaging. There is no
commit history, no other branches, and no way to check out an older commit from the
archive itself — it is the working tree only, as if you'd downloaded a "Source code"
zip from a GitHub release page.

**One copy per repo.** The tool intentionally does not keep dated snapshots. Each
repo maps to exactly one tarball. Re-running the archive command against a repo
whose remote hasn't changed is a no-op (aside from a cheap existence check);
re-running against a repo that *has* changed deletes the old tarball and replaces
it with a new one.

**SHA-based change detection.** "Has this repo changed" is answered by comparing the
last-recorded commit SHA of the tracked branch against the current remote SHA via
`git ls-remote` — a lightweight network call that doesn't require cloning anything.
This is what makes `archive-repo update` fast enough to run frequently.

---

## Usage

### Archive a single repository

```sh
archive-repo <github-url> [branch]
```

- `<github-url>` — HTTPS clone URL, e.g. `https://github.com/owner/repo` (with or
  without a trailing `.git`).
- `[branch]` — optional. Defaults to the repository's default branch (`HEAD`). Pass
  a specific branch or tag name to pin the archive to it.

Example:
```sh
archive-repo https://github.com/torvalds/linux master
```

Behavior:
- If no archive exists yet for this repo → prompts with an estimated download size,
  then clones and packages it on confirmation.
- If an archive exists and the remote hasn't moved → reports "up to date" and exits
  without touching the network beyond one `ls-remote` call.
- If an archive exists and the remote *has* moved → reports the SHA change, deletes
  the old archive, and re-clones.

### Check for updates without downloading

```sh
archive-repo update
```

Iterates every previously archived repo and reports `[current]` or `[outdated]`
against each, with old/new SHA. Makes no changes.

### Update everything that's outdated

```sh
archive-repo upgrade
```

Same check as `update`, but re-archives anything reported outdated. Each upgrade
still goes through the normal size-estimate/confirm prompt.

### Archive multiple repositories at once

```sh
archive-repos <url1> <url2> <url3> ...
```

Checks status and estimated size for every URL up front, prints one combined total,
and asks for a single confirmation before downloading everything that's new or
outdated. Repos already current are skipped silently in the download phase (they're
still listed in the status output). Does not support the `[branch]` argument — always
tracks each repo's default branch.

---

## File Layout

All archives live in one flat directory (default `/tank/git`, see
[Configuration](#configuration)). For a repository named `example`:

```
example.tar.gz     # the archive itself
example.meta        # plain-text key=value metadata
```

`example.meta` contents:
```
url=https://github.com/owner/example
branch=main
sha=a1b2c3d4e5f6...
```

Both files are written `chmod 444` (read-only for all users, including the owner)
immediately after creation. This is deliberate: it prevents accidental in-place
modification of the archive. The intended usage pattern is to `cp` the tarball
somewhere else before extracting and editing anything — the archive itself should
remain a fixed, trustworthy snapshot.

When a repo is updated, the tool `chmod`s the old files back to writable internally
before deleting them, then recreates fresh read-only versions — you do not need to
do this manually.

---

## How Version Checking Works

```
                    ┌─────────────────────────┐
                    │  archive-repo <url>      │
                    └────────────┬─────────────┘
                                 │
                git ls-remote <url> <branch|HEAD>
                                 │
                    ┌────────────▼─────────────┐
                    │ Does a .meta file exist   │
                    │ for this repo already?    │
                    └──────┬─────────────┬──────┘
                           │ no          │ yes
                           │             │
                           │      compare stored sha vs remote sha
                           │             │
                           │      ┌──────┴───────┐
                           │      │ same          │ different
                           │      ▼               ▼
                           │  report "up to    delete old
                           │  date", exit      tarball + meta
                           │                       │
                           └───────────┬───────────┘
                                       ▼
                         estimate size (GitHub API), confirm
                                       │
                         git clone --depth 1, strip .git,
                         tar, chmod 444, write new .meta
```

There is intentionally no attempt to diff *content* — only the commit SHA is
compared. A repo that force-pushes a different commit but ends up with identical
file contents will still be treated as "changed" and re-downloaded.

---

## Configuration

The storage path is currently hardcoded as `dest="/tank/git"` inside each function.
To adapt this for your own environment, either:

- Edit the `dest="..."` line directly in each function, or
- Refactor to read from an environment variable, e.g.:

  ```sh
  dest="${ARCHIVE_REPO_DIR:-$HOME/repo-archives}"
  ```

  and set `export ARCHIVE_REPO_DIR=/your/path` in your shell profile before the
  functions are defined.

No other paths in the script are environment-specific.

---

## Troubleshooting

**`sed: command 'r' uses only one address`**
You're on BusyBox `sed` (common on Alpine) and tried a range-based insert
(`addr1,addr2r file`). BusyBox's `r` command only accepts a single line address.
Use a single line number instead: `sed -i 'Nr /path/to/file' target`.

**Estimated size shows `~0 MB` or is missing**
The GitHub API lookup failed — usually a private repo (unauthenticated requests
can't see it), a typo in the URL, or you've hit GitHub's unauthenticated rate limit
(60 requests/hour/IP). The archive will still proceed; only the size preview is
affected.

**`archive-repo update` reports everything as current, but you know a repo changed**
Check that `git ls-remote` can actually reach GitHub from this machine (proxy/DNS/
firewall issues will cause the remote SHA lookup to return empty, which the script
currently treats as "no change detected" rather than erroring loudly — see
[Limitations](#known-limitations)).

**Archive won't delete / "Permission denied" on manual `rm`**
Files are `chmod 444`. Run `chmod 644 <file>` first, or let the tool handle
replacement automatically by re-running `archive-repo <url>`.

**Cloning a very large repository takes a long time or fills disk**
`--depth 1` avoids full history, but a repo with large binary assets in its working
tree (e.g. bundled datasets, large images/media) will still produce a large tarball.
Check the size estimate before confirming.

---

## Known Limitations

- **No authentication support.** Private repositories and API rate limits beyond
  60 requests/hour are not handled. Adding a `GITHUB_TOKEN` environment variable
  passed as an `Authorization` header to the `curl` calls, and using an
  authenticated HTTPS clone URL for `git`, would be the natural extension point.
- **SHA comparison only, not content diffing.** See [Version Checking](#how-version-checking-works).
- **Silent failure on network errors during SHA lookup.** If `git ls-remote` fails,
  the script currently falls through with an empty SHA rather than raising a clear
  error. This can cause `update`/`upgrade` to under-report changes if run during a
  network outage.
- **`archive-repos` does not support per-repo branch pinning.** Only the default
  branch is tracked in batch mode.
- **Not a full mirror.** No commit history, issues, releases, wiki, or LFS objects
  are captured — only the working tree of one branch at clone time.

---

## Extending the Script

Reasonable next steps for contributors:

- **Config file support** — read defaults (storage path, default branch behavior)
  from a `.archive-reporc` instead of hardcoded variables.
- **Cron-friendly non-interactive mode** — a `--yes`/`-y` flag to skip the size
  confirmation prompt, so `archive-repo upgrade` can run unattended on a schedule.
- **GitHub token support** — for private repos and higher API rate limits.
- **Checksum verification** — store a SHA-256 of the tarball itself in `.meta`
  alongside the git commit SHA, so integrity can be verified independent of git.
- **Non-GitHub remotes** — the `curl`-based size check is GitHub-API-specific;
  supporting GitLab/Bitbucket/generic git remotes would require making that check
  optional or provider-aware.

Pull requests should preserve POSIX shell compatibility (no bashisms) so the tool
keeps working on minimal environments like Alpine/BusyBox.
