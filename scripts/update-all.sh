#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for script in "$script_dir"/update-*.sh; do
	[[ -x "$script" ]] || continue
	[[ "$(basename "$script")" != "update-all.sh" ]] || continue
	echo "=========================================="
	echo "Running $(basename "$script")..."
	echo "=========================================="
	"$script"
	echo ""
done

echo "=========================================="
echo "Running update-issues.sh for matrix-org/synapse..."
echo "=========================================="
GH_REPO="matrix-org/synapse" TARGET_DIR="issues-synapse" "$script_dir/update-issues.sh"
echo ""
