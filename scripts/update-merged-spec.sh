#!/usr/bin/env bash
set -euo pipefail

SOURCE_REPO="${SOURCE_REPO:-}"
SOURCE_REF="${SOURCE_REF:-HEAD}"

managed_paths=(
	appendices.txt
	application-service-api.txt
	changelog
	client-server-api
	generate_llm_spec_tree.py
	identity-service-api.txt
	index.txt
	olm-megolm
	proposals.txt
	push-gateway-api.txt
	rooms
	server-server-api.txt
)

if ! command -v git >/dev/null 2>&1; then
	echo "error: git is required" >&2
	exit 1
fi

if [[ -z "$SOURCE_REPO" ]]; then
	echo "error: SOURCE_REPO must point at a checkout containing the plain-text spec files" >&2
	echo "example: SOURCE_REPO=../matrix-spec-plain ./scripts/update-merged-spec.sh" >&2
	exit 1
fi

git -C "$SOURCE_REPO" rev-parse --git-dir >/dev/null

tmp_dir="$(mktemp -d "merged-spec.tmp.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

manifest="$tmp_dir/files.txt"
: >"$manifest"

for path in "${managed_paths[@]}"; do
	if git -C "$SOURCE_REPO" cat-file -e "$SOURCE_REF:$path" 2>/dev/null; then
		printf '%s\n' "$path" >>"$manifest"
		continue
	fi

	git -C "$SOURCE_REPO" ls-tree -r --name-only "$SOURCE_REF" "$path" >>"$manifest"
done

sort -u "$manifest" -o "$manifest"

count="$(wc -l <"$manifest")"
if [[ "$count" -eq 0 ]]; then
	echo "error: no managed spec files found in $SOURCE_REPO at $SOURCE_REF" >&2
	echo "refusing to delete local files" >&2
	exit 1
fi

echo "syncing plain-text spec files from $SOURCE_REPO ($SOURCE_REF)"

find . \
	\( -path './.git' -o -path './.ruff_cache' -o -path './proposals' -o -path './scripts' \) -prune -o \
	-type f -print |
	while read -r path; do
		trimmed="${path#./}"
		case "$trimmed" in
		appendices.txt|application-service-api.txt|generate_llm_spec_tree.py|identity-service-api.txt|index.txt|proposals.txt|push-gateway-api.txt|server-server-api.txt)
			grep -Fxq "$trimmed" "$manifest" || rm -f -- "$trimmed"
			;;
		changelog/*|client-server-api/*|olm-megolm/*|rooms/*)
			grep -Fxq "$trimmed" "$manifest" || rm -f -- "$trimmed"
			;;
		esac
	done

echo "copying refreshed spec files"
while read -r path; do
	[[ -n "$path" ]] || continue
	dest_dir="$(dirname "$path")"
	if [[ "$dest_dir" != "." ]]; then
		mkdir -p "$dest_dir"
	fi
	git -C "$SOURCE_REPO" show "$SOURCE_REF:$path" >"$path"
done <"$manifest"

echo "wrote $count merged spec files from $SOURCE_REPO"
