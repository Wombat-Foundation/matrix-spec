#!/usr/bin/env bash
set -euo pipefail

SOURCE_REPO="${SOURCE_REPO:-../proposals}"
TARGET_DIR="${TARGET_DIR:-proposals}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_MAIN="${UPSTREAM_MAIN:-upstream/main}"
MANIFEST_PATH="${MANIFEST_PATH:-$TARGET_DIR/SOURCES.tsv}"

if ! command -v git >/dev/null 2>&1; then
	echo "error: git is required" >&2
	exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
	echo "error: rg is required" >&2
	exit 1
fi

git -C "$SOURCE_REPO" rev-parse --git-dir >/dev/null

mkdir -p "$TARGET_DIR"

echo "fetching upstream main from $SOURCE_REPO"
git -C "$SOURCE_REPO" fetch "$UPSTREAM_REMOTE" \
	'+refs/heads/main:refs/remotes/upstream/main'

tmp_dir="$(mktemp -d "${TARGET_DIR}.tmp.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

manifest_rel="${MANIFEST_PATH#$TARGET_DIR/}"
printf 'file\tref\n' >"$tmp_dir/SOURCES.tsv"

while read -r path; do
	[[ -n "$path" ]] || continue

	rel="${path#proposals/}"
	out="$tmp_dir/$rel"
	mkdir -p "$(dirname "$out")"
	git -C "$SOURCE_REPO" show "$UPSTREAM_MAIN:$path" >"$out"
	printf '%s\t%s\n' "$rel" "$UPSTREAM_MAIN" >>"$tmp_dir/SOURCES.tsv"
done < <(
	git -C "$SOURCE_REPO" ls-tree -r --name-only "$UPSTREAM_MAIN" -- proposals |
		rg '^proposals/' |
		rg -v '^proposals/(unmerged|forks)/' |
		rg -v '^proposals/SOURCES\.tsv$'
)

if [[ -f "$MANIFEST_PATH" ]]; then
	echo "removing files from previous manifest"
	tail -n +2 "$MANIFEST_PATH" |
		while IFS=$'\t' read -r file _ref; do
			[[ -n "$file" ]] || continue
			case "$file" in
			"" | .* | */../* | ../* | */.. | ..) continue ;;
			esac
			rm -f -- "$TARGET_DIR/$file"
		done
fi

echo "copying refreshed files to $TARGET_DIR"
find "$tmp_dir" -type f ! -name 'SOURCES.tsv' -print0 |
	while IFS= read -r -d '' src; do
		rel="${src#$tmp_dir/}"
		dest="$TARGET_DIR/$rel"
		mkdir -p "$(dirname "$dest")"
		cp -- "$src" "$dest"
	done

cp -- "$tmp_dir/SOURCES.tsv" "$MANIFEST_PATH"

count="$(tail -n +2 "$tmp_dir/SOURCES.tsv" | wc -l)"
echo "wrote $count merged proposal files to $TARGET_DIR"
echo "updated manifest at $MANIFEST_PATH"
