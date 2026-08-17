#!/usr/bin/env bash
set -euo pipefail

SOURCE_REPO="${SOURCE_REPO:-}"
SOURCE_REF="${SOURCE_REF:-HEAD}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
parent_dir="$(dirname "$repo_root")"

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

infer_source_repo() {
	local candidate
	local matches=()

	for candidate in "$parent_dir"/*; do
		[[ -d "$candidate" ]] || continue
		[[ "$candidate" != "$repo_root" ]] || continue
		git -C "$candidate" rev-parse --git-dir >/dev/null 2>&1 || continue
		[[ -f "$candidate/appendices.txt" ]] || continue
		[[ -f "$candidate/index.txt" ]] || continue
		[[ -f "$candidate/server-server-api.txt" ]] || continue
		[[ -d "$candidate/client-server-api" ]] || continue
		matches+=("$candidate")
	done

	case "${#matches[@]}" in
	0)
		return 1
		;;
	1)
		printf '%s\n' "${matches[0]}"
		;;
	*)
		echo "error: multiple candidate plain-text spec checkouts found:" >&2
		printf '  %s\n' "${matches[@]}" >&2
		echo "set SOURCE_REPO explicitly" >&2
		return 1
		;;
	esac
}

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_MAIN="${UPSTREAM_MAIN:-upstream/main}"

if [[ -z "$SOURCE_REPO" ]]; then
	if SOURCE_REPO="$(infer_source_repo)"; then
		echo "auto-detected SOURCE_REPO=$SOURCE_REPO"
	else
		echo "no unique sibling plain-text checkout found; using current repository ($repo_root)"
		SOURCE_REPO="$repo_root"
	fi
fi

git -C "$SOURCE_REPO" rev-parse --git-dir >/dev/null

tmp_dir="$(mktemp -d "merged-spec.tmp.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

manifest="$tmp_dir/files.txt"
: >"$manifest"

for path in "${managed_paths[@]}"; do
	obj_type="$(git -C "$SOURCE_REPO" cat-file -t "$SOURCE_REF:$path" 2>/dev/null || true)"
	if [[ "$obj_type" == "blob" ]]; then
		printf '%s\n' "$path" >>"$manifest"
	elif [[ "$obj_type" == "tree" ]]; then
		git -C "$SOURCE_REPO" ls-tree -r --name-only "$SOURCE_REF" "$path" >>"$manifest"
	fi
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
		appendices.txt | application-service-api.txt | generate_llm_spec_tree.py | identity-service-api.txt | index.txt | proposals.txt | push-gateway-api.txt | server-server-api.txt)
			grep -Fxq "$trimmed" "$manifest" || rm -f -- "$trimmed"
			;;
		changelog/* | client-server-api/* | olm-megolm/* | rooms/*)
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
