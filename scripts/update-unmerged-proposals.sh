#!/usr/bin/env bash
set -euo pipefail

SOURCE_REPO="${SOURCE_REPO:-../proposals}"
TARGET_DIR="${TARGET_DIR:-proposals/unmerged}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_MAIN="${UPSTREAM_MAIN:-upstream/main}"
GH_REPO="${GH_REPO:-matrix-org/matrix-spec-proposals}"

if ! command -v gh >/dev/null 2>&1; then
	echo "error: gh is required" >&2
	exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
	echo "error: rg is required" >&2
	exit 1
fi

git -C "$SOURCE_REPO" rev-parse --git-dir >/dev/null

mkdir -p "$TARGET_DIR"

git -C "$SOURCE_REPO" fetch "$UPSTREAM_REMOTE" \
	'+refs/pull/*/head:refs/pr/upstream/*'

find "$TARGET_DIR" -maxdepth 1 -type f -delete
printf 'file\tpr\tref\n' >"$TARGET_DIR/SOURCES.tsv"

gh pr list \
	-R "$GH_REPO" \
	--state open \
	--limit 1000 \
	--json number \
	--jq '.[].number' |
	sort -n |
	while read -r pr; do
		ref="refs/pr/upstream/$pr"

		git -C "$SOURCE_REPO" rev-parse --verify --quiet "$ref" >/dev/null || continue

		git -C "$SOURCE_REPO" diff \
			--name-only \
			--diff-filter=AMR \
			"$UPSTREAM_MAIN...$ref" 2>/dev/null |
			rg '^proposals/[0-9][^/]*\.md$' |
			while read -r path; do
				out="$TARGET_DIR/${path#proposals/}"

				git -C "$SOURCE_REPO" show "$ref:$path" >"$out"
				printf '%s\t%s\t%s\n' "${path#proposals/}" "$pr" "$ref" >>"$TARGET_DIR/SOURCES.tsv"
			done
	done

count="$(find "$TARGET_DIR" -maxdepth 1 -type f -name '[0-9]*.md' | wc -l)"
echo "wrote $count proposal files to $TARGET_DIR"
