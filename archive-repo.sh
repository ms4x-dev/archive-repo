#!/bin/sh
# archive-repo.sh
#
# Lightweight GitHub repo snapshotting: latest branch/tag, no history,
# stored as a single read-only tarball per repo, replaced automatically
# when the source updates.
#
# See DOCUMENTATION.md for full usage, internals, and troubleshooting.
#
# Installation:
#   cat archive-repo.sh >> ~/.profile   # or ~/.bashrc, ~/.zshrc, etc.
#   source ~/.profile
#
# Configuration:
#   Set ARCHIVE_REPO_DIR before sourcing this file to change where
#   archives are stored. Defaults to "$HOME/repo-archives".
#
#     export ARCHIVE_REPO_DIR=/your/path
#
# Requirements: git, curl, tar, sed, grep, awk, basename (POSIX shell only,
# no bashisms — works on ash/dash/bash/BusyBox).

archive-repo() {
    dest="${ARCHIVE_REPO_DIR:-$HOME/repo-archives}"
    mkdir -p "$dest"

    if [ "$1" = "update" ]; then
        for meta in "$dest"/*.meta; do
            [ -f "$meta" ] || continue
            name=$(basename "$meta" .meta)
            url=$(grep '^url=' "$meta" | cut -d= -f2-)
            branch=$(grep '^branch=' "$meta" | cut -d= -f2-)
            local_sha=$(grep '^sha=' "$meta" | cut -d= -f2)
            ref="${branch:-HEAD}"
            remote_sha=$(git ls-remote "$url" "$ref" 2>/dev/null | awk '{print $1}' | head -1)
            [ -z "$remote_sha" ] && remote_sha=$(git ls-remote "$url" HEAD 2>/dev/null | awk '{print $1}' | head -1)
            if [ "$local_sha" = "$remote_sha" ]; then
                echo "  [current]  $name"
            else
                echo "  [outdated] $name  ($local_sha -> $remote_sha)"
            fi
        done
        return 0
    fi

    if [ "$1" = "upgrade" ]; then
        for meta in "$dest"/*.meta; do
            [ -f "$meta" ] || continue
            url=$(grep '^url=' "$meta" | cut -d= -f2-)
            branch=$(grep '^branch=' "$meta" | cut -d= -f2-)
            local_sha=$(grep '^sha=' "$meta" | cut -d= -f2)
            ref="${branch:-HEAD}"
            remote_sha=$(git ls-remote "$url" "$ref" 2>/dev/null | awk '{print $1}' | head -1)
            [ -z "$remote_sha" ] && remote_sha=$(git ls-remote "$url" HEAD 2>/dev/null | awk '{print $1}' | head -1)
            if [ "$local_sha" != "$remote_sha" ]; then
                echo "Upgrading $(basename "$meta" .meta)..."
                archive-repo "$url" "$branch"
            fi
        done
        return 0
    fi

    url="$1"
    [ -z "$url" ] && { echo "usage: archive-repo <github-url> [branch] | archive-repo update | archive-repo upgrade"; return 1; }
    branch="$2"
    name=$(basename "$url" .git)
    meta="$dest/${name}.meta"
    tarball="$dest/${name}.tar.gz"

    ref="${branch:-HEAD}"
    remote_sha=$(git ls-remote "$url" "$ref" 2>/dev/null | awk '{print $1}' | head -1)
    [ -z "$remote_sha" ] && remote_sha=$(git ls-remote "$url" HEAD 2>/dev/null | awk '{print $1}' | head -1)

    if [ -f "$meta" ]; then
        local_sha=$(grep '^sha=' "$meta" | cut -d= -f2)
        if [ "$local_sha" = "$remote_sha" ]; then
            echo "Up to date: $name ($local_sha)"
            [ -f "$tarball" ] && echo "  verified: $tarball" || echo "  WARNING: meta exists but tarball missing"
            return 0
        else
            echo "Newer version found for $name ($local_sha -> $remote_sha), replacing..."
            chmod 644 "$tarball" 2>/dev/null
            rm -f "$tarball" "$meta"
        fi
    fi

    owner_repo=$(echo "$url" | sed -E 's#https://github.com/##; s#\.git$##')
    size_kb=$(curl -s "https://api.github.com/repos/$owner_repo" | grep '"size"' | head -1 | grep -oE '[0-9]+')
    [ -z "$size_kb" ] && size_kb=0
    echo "Estimated size: ~$((size_kb / 1024)) MB"
    printf "Proceed? [y/N] "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { echo "Cancelled."; return 1; }

    tmp="/tmp/${name}"
    rm -rf "$tmp"

    if [ -n "$branch" ]; then
        git clone --depth 1 --branch "$branch" "$url" "$tmp" || return 1
    else
        git clone --depth 1 "$url" "$tmp" || return 1
    fi

    rm -rf "$tmp/.git"
    tar czf "$tarball" -C /tmp "$name"
    chmod 444 "$tarball"
    rm -rf "$tmp"

    echo "url=$url" > "$meta"
    echo "branch=$branch" >> "$meta"
    echo "sha=$remote_sha" >> "$meta"
    chmod 444 "$meta"

    echo "-> $tarball"
}

archive-repos() {
    dest="${ARCHIVE_REPO_DIR:-$HOME/repo-archives}"
    mkdir -p "$dest"
    total_kb=0
    to_process=""

    echo "Checking status..."
    for url in "$@"; do
        name=$(basename "$url" .git)
        meta="$dest/${name}.meta"
        remote_sha=$(git ls-remote "$url" HEAD 2>/dev/null | awk '{print $1}' | head -1)

        if [ -f "$meta" ]; then
            local_sha=$(grep '^sha=' "$meta" | cut -d= -f2)
            if [ "$local_sha" = "$remote_sha" ]; then
                echo "  [current]  $name"
                continue
            else
                echo "  [outdated] $name  ($local_sha -> $remote_sha)"
            fi
        else
            echo "  [new]      $name"
        fi

        owner_repo=$(echo "$url" | sed -E 's#https://github.com/##; s#\.git$##')
        size_kb=$(curl -s "https://api.github.com/repos/$owner_repo" | grep '"size"' | head -1 | grep -oE '[0-9]+')
        [ -z "$size_kb" ] && size_kb=0
        printf "             ~%s MB\n" "$((size_kb / 1024))"
        total_kb=$((total_kb + size_kb))
        to_process="$to_process $url"
    done

    if [ -z "$to_process" ]; then
        echo ""
        echo "All repos already up to date."
        return 0
    fi

    echo ""
    echo "Total to download: ~$((total_kb / 1024)) MB"
    printf "Proceed? [y/N] "
    read confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { echo "Cancelled."; return 1; }

    for url in $to_process; do
        name=$(basename "$url" .git)
        meta="$dest/${name}.meta"
        tarball="$dest/${name}.tar.gz"
        tmp="/tmp/${name}"
        rm -rf "$tmp"

        echo "Cloning $name..."
        git clone --depth 1 "$url" "$tmp" >/dev/null 2>&1 || { echo "  FAILED: $name"; continue; }

        remote_sha=$(git ls-remote "$url" HEAD 2>/dev/null | awk '{print $1}' | head -1)

        chmod 644 "$tarball" 2>/dev/null
        rm -f "$tarball" "$meta"

        rm -rf "$tmp/.git"
        tar czf "$tarball" -C /tmp "$name"
        chmod 444 "$tarball"
        rm -rf "$tmp"

        echo "url=$url" > "$meta"
        echo "sha=$remote_sha" >> "$meta"
        chmod 444 "$meta"

        echo "  -> $tarball"
    done
}
