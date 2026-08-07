#!/usr/bin/env bash
# set-stable.sh <product> <platform> <version>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source "$(dirname "$0")/common.sh"
need jq
need date

product="${1:?}"
platform="${2:?}"
version="${3:?}"
file="$(channel_file "$product" "$platform")"

[[ -f "$file" ]] || { echo "missing $file" >&2; exit 1; }

jq -e --arg v "$version" '.builds[$v] != null' "$file" >/dev/null || {
  echo "unknown build $version in $file (run sync first)" >&2
  exit 1
}

if [[ "$product" == legacy ]]; then
  url="$(jq -r --arg v "$version" '.builds[$v].url // empty' "$file")"
  if ! is_master_url "$url"; then
    echo "refusing stable pin: $version is not a master URL" >&2
    exit 1
  fi
fi

tmp="$(mktemp)"
jq --arg v "$version" '.stable = $v' "$file" >"$tmp"
mv "$tmp" "$file"

write_index "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "stable $product/$platform → $version"
