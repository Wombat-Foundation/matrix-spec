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

rm -f -- "$TARGET_DIR"/*.json "$TARGET_DIR"/*.md "$TARGET_DIR"/issues.tsv

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

cp -- "$tmp_dir/issues.json" "$TARGET_DIR/issues.json"

python3 -c '
import json, os

target_dir = os.environ.get("TARGET_DIR", "issues")
issues_file = os.path.join(target_dir, "issues.json")

def to_yaml_val(val):
    if isinstance(val, str):
        return json.dumps(val, ensure_ascii=False)
    return str(val)

if os.path.exists(issues_file):
    with open(issues_file, "r", encoding="utf-8") as f:
        issues = json.load(f)
    for issue in issues:
        num = issue.get("number")
        if not num:
            continue
        
        # Save individual raw JSON
        with open(os.path.join(target_dir, f"{num}.json"), "w", encoding="utf-8") as f_json:
            json.dump(issue, f_json, indent=2, ensure_ascii=False)
            f_json.write("\n")
        
        # Save individual YAML-frontmatter Markdown (.md)
        title = issue.get("title", "")
        state = issue.get("state", "")
        author = (issue.get("user") or {}).get("login", "unknown")
        created = issue.get("created_at", "")
        updated = issue.get("updated_at", "")
        url = issue.get("html_url") or issue.get("url", "")
        labels = [l.get("name", "") for l in issue.get("labels", []) if isinstance(l, dict)]
        body = issue.get("body") or ""
        
        yaml_lines = [
            "---",
            f"number: {num}",
            f"title: {to_yaml_val(title)}",
            f"state: {to_yaml_val(state)}",
            f"author: {to_yaml_val(author)}",
            f"created_at: {to_yaml_val(created)}",
            f"updated_at: {to_yaml_val(updated)}",
            f"url: {to_yaml_val(url)}",
        ]
        if labels:
            yaml_lines.append("labels:")
            for lbl in labels:
                yaml_lines.append(f"  - {to_yaml_val(lbl)}")
        else:
            yaml_lines.append("labels: []")
        yaml_lines.append("---")
        yaml_lines.append("")
        yaml_lines.append(body)
        
        md_content = "\n".join(yaml_lines) + "\n"
        with open(os.path.join(target_dir, f"{num}.md"), "w", encoding="utf-8") as f_out:
            f_out.write(md_content)
'

echo "updated $TARGET_DIR with JSON, TSV, and YAML-frontmatter Markdown files."
