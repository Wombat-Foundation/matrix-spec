#!/usr/bin/env bash
set -euo pipefail

SYNAPSE_REPO="${SYNAPSE_REPO:-../synapse}"
SYNAPSE_REF="${SYNAPSE_REF:-upstream/develop}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
TARGET_DIR="${TARGET_DIR:-release-notes-synapse}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

if ! command -v git >/dev/null 2>&1; then
	echo "error: git is required" >&2
	exit 1
fi

git -C "$SYNAPSE_REPO" rev-parse --git-dir >/dev/null

echo "fetching Synapse release notes from $SYNAPSE_REPO"
git -C "$SYNAPSE_REPO" fetch "$UPSTREAM_REMOTE" \
	'+refs/heads/develop:refs/remotes/upstream/develop'

tmp_dir="$(mktemp -d "synapse-release-notes.tmp.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

printf 'file\tref\n' >"$tmp_dir/SOURCES.tsv"

while read -r path; do
	[[ -n "$path" ]] || continue
	dest="$tmp_dir/$path"
	mkdir -p "$(dirname "$dest")"
	git -C "$SYNAPSE_REPO" show "$SYNAPSE_REF:$path" >"$dest"
	printf '%s\t%s\n' "$path" "$SYNAPSE_REF" >>"$tmp_dir/SOURCES.tsv"
done < <(
	git -C "$SYNAPSE_REPO" ls-tree -r --name-only "$SYNAPSE_REF" -- \
		CHANGES.md changelog.d docs/changelogs
)

mkdir -p "$TARGET_DIR"

if [[ -f "$TARGET_DIR/SOURCES.tsv" ]]; then
	echo "removing files from previous manifest"
	tail -n +2 "$TARGET_DIR/SOURCES.tsv" |
		while IFS=$'\t' read -r path _ref; do
			case "$path" in
			CHANGES.md | changelog.d/* | docs/changelogs/*) rm -f -- "$TARGET_DIR/$path" ;;
			esac
		done
fi

echo "copying refreshed Synapse release notes to $TARGET_DIR"
find "$tmp_dir" -type f -print0 |
	while IFS= read -r -d '' source; do
		relative="${source#"$tmp_dir"/}"
		destination="$TARGET_DIR/$relative"
		mkdir -p "$(dirname "$destination")"
		cp -- "$source" "$destination"
	done

count="$(tail -n +2 "$tmp_dir/SOURCES.tsv" | wc -l)"
echo "wrote $count Synapse release-note files to $TARGET_DIR"
