#!/usr/bin/env bash
# set-stable.sh <product> <platform> <version>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source "$(dirname "$0")/common.sh"
need jq

product="${1:?}"
platform="${2:?}"
version="${3:?}"
file="$(channel_file "$product" "$platform")"

[[ -f "$file" ]] || { echo "missing $file" >&2; exit 1; }

jq -e --arg v "$version" '.builds[$v] != null' "$file" >/dev/null || {
  echo "unknown build $version in $file (run sync first)" >&2
  exit 1
}

tmp="$(mktemp)"
jq --arg v "$version" '.stable = $v' "$file" >"$tmp"
mv "$tmp" "$file"

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
tmp="$(mktemp)"
jq -n \
  --arg updatedAt "$now" \
  --argjson lw "$(jq '{latest,stable}' versions/legacy/win32.json)" \
  --argjson ll "$(jq '{latest,stable}' versions/legacy/linux.json)" \
  --argjson ew "$(jq '{latest,stable}' versions/enhanced/win32.json)" \
  --argjson el "$(jq '{latest,stable}' versions/enhanced/linux.json)" \
  '{
    updatedAt: $updatedAt,
    channels: {
      "legacy/win32": ($lw + {path: "versions/legacy/win32.json"}),
      "legacy/linux": ($ll + {path: "versions/legacy/linux.json"}),
      "enhanced/win32": ($ew + {path: "versions/enhanced/win32.json"}),
      "enhanced/linux": ($el + {path: "versions/enhanced/linux.json"})
    }
  }' >"$tmp"
mv "$tmp" versions/index.json

echo "stable $product/$platform → $version"
