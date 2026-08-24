#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="${TARGET_DIR:-proposals/unmerged}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-origin}"
UPSTREAM_MAIN="${UPSTREAM_MAIN:-origin/main}"
GH_REPO="${GH_REPO:-matrix-org/matrix-spec-proposals}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
SOURCE_REPO="${SOURCE_REPO:-$repo_root/ext/proposals}"
cd "$repo_root"

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

echo "fetching upstream main and PR heads from $SOURCE_REPO"
git -C "$SOURCE_REPO" fetch "$UPSTREAM_REMOTE" \
	"+refs/heads/main:refs/remotes/$UPSTREAM_REMOTE/main" \
	'+refs/pull/*/head:refs/pr/source/*'

tmp_dir="$(mktemp -d "${TARGET_DIR}.tmp.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

printf 'file\tpr\tref\n' >"$tmp_dir/SOURCES.tsv"

echo "listing open PRs for $GH_REPO"
open_prs="$(gh pr list \
	-R "$GH_REPO" \
	--state open \
	--limit 1000 \
	--json number \
	--jq '.[].number' |
	sort -n)"

pr_count="$(printf '%s\n' "$open_prs" | sed '/^$/d' | wc -l)"
echo "processing $pr_count open PRs"

while read -r pr; do
	[[ -n "$pr" ]] || continue

	ref="refs/pr/source/$pr"

	git -C "$SOURCE_REPO" rev-parse --verify --quiet "$ref" >/dev/null || continue

	paths="$(git -C "$SOURCE_REPO" diff \
		--name-only \
		--diff-filter=AMR \
		"$UPSTREAM_MAIN...$ref" 2>/dev/null |
		rg '^proposals/[0-9][^/]*\.md$' || true)"

	while read -r path; do
		[[ -n "$path" ]] || continue
		out="$tmp_dir/${path#proposals/}"

		git -C "$SOURCE_REPO" show "$ref:$path" >"$out"
		printf '%s\t%s\t%s\n' "${path#proposals/}" "$pr" "$ref" >>"$tmp_dir/SOURCES.tsv"
	done <<<"$paths"
done <<<"$open_prs"

if [[ -f "$TARGET_DIR/SOURCES.tsv" ]]; then
	echo "removing files from previous manifest"
	tail -n +2 "$TARGET_DIR/SOURCES.tsv" |
		while IFS=$'\t' read -r file _pr _ref; do
			[[ -n "$file" ]] || continue
			case "$file" in
			*/* | .* | "") continue ;;
			esac
			rm -f -- "$TARGET_DIR/$file"
		done
fi

echo "copying refreshed files to $TARGET_DIR"
find "$tmp_dir" -maxdepth 1 -type f -exec cp -- '{}' "$TARGET_DIR/" ';'

count="$(find "$tmp_dir" -maxdepth 1 -type f -name '[0-9]*.md' | wc -l)"
echo "wrote $count proposal files to $TARGET_DIR"
