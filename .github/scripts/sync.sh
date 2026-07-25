#!/usr/bin/env bash
# sync.sh — discover all channels, update versions/*.json + index.json (no downloads)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source "$(dirname "$0")/common.sh"
need curl
need jq
need date

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
changed=0

upsert() {
  local product="$1" platform="$2" version="$3" url="$4"
  local file
  file="$(channel_file "$product" "$platform")"

  local tmp
  tmp="$(mktemp)"
  jq \
    --arg version "$version" \
    --arg url "$url" \
    --arg seenAt "$now" \
    '
      .latest = $version
      | .builds[$version] = (
          (.builds[$version] // {})
          + { url: $url, seenAt: $seenAt }
        )
    ' "$file" >"$tmp"

  if ! cmp -s "$file" "$tmp"; then
    mv "$tmp" "$file"
    changed=1
    echo "updated $product/$platform → $version"
  else
    rm -f "$tmp"
    echo "unchanged $product/$platform ($version)"
  fi
}

# Also record Legacy recommended (often differs from latest).
upsert_legacy_recommended() {
  local platform="$1"
  local data version url
  data="$(curl -fsSL "https://changelogs-live.fivem.net/api/changelog/versions/${platform}/server")"
  version="$(echo "$data" | jq -r '.recommended // empty')"
  url="$(echo "$data" | jq -r '.recommended_download // empty')"
  [[ -n "$version" && -n "$url" ]] || return 0

  local file tmp
  file="$(channel_file legacy "$platform")"
  tmp="$(mktemp)"
  jq \
    --arg version "$version" \
    --arg url "$url" \
    --arg seenAt "$now" \
    '
      .builds[$version] = (
        (.builds[$version] // {})
        + { url: $url, seenAt: $seenAt }
      )
    ' "$file" >"$tmp"

  if ! cmp -s "$file" "$tmp"; then
    mv "$tmp" "$file"
    changed=1
    echo "recorded legacy/$platform recommended $version"
  else
    rm -f "$tmp"
  fi
}

for product in legacy enhanced; do
  for platform in win32 linux; do
    line="$("$(dirname "$0")/discover.sh" "$product" "$platform")"
    version="${line%%$'\t'*}"
    url="${line#*$'\t'}"
    upsert "$product" "$platform" "$version" "$url"
  done
done

upsert_legacy_recommended win32
upsert_legacy_recommended linux

# Rebuild index summary
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

if ! cmp -s versions/index.json "$tmp"; then
  mv "$tmp" versions/index.json
  changed=1
else
  rm -f "$tmp"
fi

if [[ "$changed" -eq 1 ]]; then
  echo "catalog changed"
  exit 0
fi
echo "catalog unchanged"
exit 0
