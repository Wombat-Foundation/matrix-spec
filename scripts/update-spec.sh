#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
SOURCE_REPO="${SOURCE_REPO:-$repo_root/ext/spec}"
SOURCE_REF="${SOURCE_REF:-HEAD}"
cd "$repo_root"

if ! command -v git >/dev/null 2>&1; then
	echo "error: git is required" >&2
	exit 1
fi

git -C "$SOURCE_REPO" rev-parse --git-dir >/dev/null
git -C "$SOURCE_REPO" cat-file -e "$SOURCE_REF:content" 2>/dev/null || {
	echo "error: no Matrix spec content found in $SOURCE_REPO at $SOURCE_REF" >&2
	echo "initialize submodules with: git submodule update --init --recursive" >&2
	exit 1
}

tmp_dir="$(mktemp -d "$repo_root/merged-spec.tmp.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT
source_tree="$tmp_dir/source"
output_tree="$tmp_dir/output"
mkdir -p "$source_tree" "$output_tree"

echo "exporting Matrix spec sources from $SOURCE_REPO ($SOURCE_REF)"
git -C "$SOURCE_REPO" archive "$SOURCE_REF" |
	tar -x -C "$source_tree"

(
	cd "$source_tree"
	python3 "$repo_root/scripts/generate_txt_spec_tree.py" \
		--source-root content \
		--output-root "$output_tree"
)

if ! find "$output_tree" -type f -name '*.txt' -print -quit | grep -q .; then
	echo "error: generator produced no spec files; refusing to replace spec/" >&2
	exit 1
fi

echo "replacing generated plain-text corpus"
rm -rf -- spec
mv -- "$output_tree" spec

count="$(find spec -type f -name '*.txt' | wc -l)"
echo "wrote $count generated spec files from $SOURCE_REPO"
