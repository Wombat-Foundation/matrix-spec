#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$repo_root"

tmp_file="$(mktemp)"
tmp_rows="$(mktemp)"
trap 'rm -f "$tmp_file" "$tmp_rows"' EXIT

: >"$tmp_rows"

find proposals -maxdepth 2 -type f -name '*.md' ! -path 'proposals/forks/*' | sort | while read -r path; do
    child="$(basename "$path" .md)"
    child="${child%%-*}"

    awk -v path="$path" -v child="$child" '
    BEGIN {
        RS = ""
        FS = "\n"
    }

    function emit(parent, relation, confidence, evidence) {
        gsub(/\t/, " ", evidence)
        gsub(/\n+/, " ", evidence)
        gsub(/[[:space:]]+/, " ", evidence)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", evidence)
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", child, parent, relation, confidence, path, evidence
    }

    function emit_all(segment, relation, confidence, evidence) {
        while (match(segment, /MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/, m)) {
            emit(m[1], relation, confidence, evidence)
            segment = substr(segment, RSTART + RLENGTH)
        }
    }

    {
        line = $0

        if (match(line, /supersedes[^[]*\[MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "supersedes", "direct", $0)
        } else if (match(line, /supersedes[^M]*MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "supersedes", "direct", $0)
        }

        if (match(line, /superseded by[^[]*\[MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "superseded_by", "direct", $0)
        } else if (match(line, /superseded by[^M]*MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "superseded_by", "direct", $0)
        }

        if (match(line, /replaces[^[]*\[MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "replaces", "direct", $0)
        } else if (match(line, /replaces[^M]*MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "replaces", "direct", $0)
        }

        if (match(line, /parallel exploration of[^[]*\[MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit(m[1], "parallel_exploration", "direct", $0)
        } else if (match(line, /parallel exploration to[^[]*\[MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit(m[1], "parallel_exploration", "direct", $0)
        }

        if (match(line, /incorporates the ideas of[^.]*successive attempts[^:]*:/)) {
            emit_all(substr(line, RSTART + RLENGTH), "incorporates_attempt", "direct", $0)
        }

        if (match(line, /builds on[^[]*\[MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "builds_on", "derived", $0)
        } else if (match(line, /builds on[^M]*MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "builds_on", "derived", $0)
        }

        if (match(line, /This builds on[^[]*\[MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "builds_on", "derived", $0)
        }

        if (match(line, /(This MSC|This proposal)[^.\n]*extends[^[]*\[MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "extends", "derived", $0)
        } else if (match(line, /(This MSC|This proposal)[^.\n]*extends[^M]*MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "extends", "derived", $0)
        }

        if (match(line, /(This MSC|This proposal|\*This proposal)[^.\n]*depends on[^[]*\[MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "depends_on", "derived", $0)
        } else if (match(line, /(This MSC|This proposal|\*This proposal)[^.\n]*depends on[^M]*MSC([0-9A-F]{3,4}|00[A-F0-9]{2}|0F[0-9A-F]{2})/ , m)) {
            emit_all(substr(line, RSTART), "depends_on", "derived", $0)
        }
    }
    ' "$path" >>"$tmp_rows"
done

{
    printf 'child_msc\tparent_msc\trelation\tconfidence\tchild_path\tevidence\n'
    sort -t $'\t' -k1,1 -k2,2 -k3,3 -k4,4 -k5,5 -k6,6 "$tmp_rows" \
        | awk -F '\t' '!seen[$1 FS $2 FS $3 FS $4 FS $5]++'
} > proposals/forks/lineage.tsv
