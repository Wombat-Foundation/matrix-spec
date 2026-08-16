#!/usr/bin/env bash
set -euo pipefail

GH_REPO="${GH_REPO:-matrix-org/matrix-spec}"
TARGET_DIR="${TARGET_DIR:-issues}"

if ! command -v gh >/dev/null 2>&1; then
	echo "error: gh is required" >&2
	exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
	echo "error: jq is required" >&2
	exit 1
fi

mkdir -p "$TARGET_DIR"

tmp_dir="$(mktemp -d "${TARGET_DIR}.tmp.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

echo "fetching issues for $GH_REPO"
gh api --paginate -H "Accept: application/vnd.github+json" \
	"/repos/$GH_REPO/issues?state=all&per_page=100" |
	jq -s 'flatten | map(select(has("pull_request") | not))' >"$tmp_dir/issues.json"

count="$(jq 'length' "$tmp_dir/issues.json")"
echo "writing $count issues to $TARGET_DIR"

rm -f -- "$TARGET_DIR"/*.json "$TARGET_DIR"/issues.tsv

jq -r '
	.[] |
	[
		.number,
		.state,
		.created_at,
		.updated_at,
		.title,
		.url
	] | @tsv
' "$tmp_dir/issues.json" >"$TARGET_DIR/issues.tsv"

jq -r '
	.[] |
	[
		.number,
		.title,
		.url
	] | @tsv
' "$tmp_dir/issues.json" |
	while IFS=$'\t' read -r number title url; do
		[[ -n "$number" ]] || continue
		jq --argjson number "$number" '
			map(select(.number == $number))[0]
		' "$tmp_dir/issues.json" >"$TARGET_DIR/$number.json"
	done

cp -- "$tmp_dir/issues.json" "$TARGET_DIR/issues.json"

echo "updated $TARGET_DIR/issues.json and $TARGET_DIR/issues.tsv"
