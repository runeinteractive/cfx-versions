#!/usr/bin/env bash
# sync.sh — discover channels, update versions/*.json + index.json (no downloads)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source "$(dirname "$0")/common.sh"
need curl
need jq
need date

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
changed=0
SCRIPTS="$(dirname "$0")"

write_if_changed() {
  local file="$1" tmp="$2" msg="$3"
  if ! cmp -s "$file" "$tmp"; then
    mv "$tmp" "$file"
    changed=1
    echo "$msg"
  else
    rm -f "$tmp"
  fi
}

upsert() {
  local product="$1" platform="$2" version="$3" url="$4"
  local file tmp
  file="$(channel_file "$product" "$platform")"
  tmp="$(mktemp)"
  jq \
    --argjson schemaVersion "$SCHEMA_VERSION" \
    --arg version "$version" \
    --arg url "$url" \
    --arg seenAt "$now" \
    '
      .schemaVersion = $schemaVersion
      | .latest = $version
      | .builds[$version] = (
          (.builds[$version] // {})
          + { url: $url, seenAt: $seenAt }
        )
    ' "$file" >"$tmp"
  if ! cmp -s "$file" "$tmp"; then
    mv "$tmp" "$file"
    changed=1
    echo "updated $product/$platform -> $version"
  else
    rm -f "$tmp"
    echo "unchanged $product/$platform ($version)"
  fi
}

# Record Cfx "recommended" when it is a master build (does not change .latest).
upsert_legacy_recommended() {
  local platform="$1"
  local data version url file tmp
  data="$(curl -fsSL "https://changelogs-live.fivem.net/api/changelog/versions/${platform}/server")"
  version="$(echo "$data" | jq -r '.recommended // empty')"
  url="$(echo "$data" | jq -r '.recommended_download // empty')"
  [[ -n "$version" && -n "$url" ]] || return 0
  if ! is_master_url "$url"; then
    echo "skip legacy/$platform recommended $version (not master)"
    return 0
  fi

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
  write_if_changed "$file" "$tmp" "recorded legacy/$platform recommended $version"
}

prune_legacy_non_master() {
  local platform="$1"
  local file tmp
  file="$(channel_file legacy "$platform")"
  tmp="$(mktemp)"
  jq '
    .builds |= with_entries(select(.value.url | test("/master/")))
    | ( [.builds | keys[] | select(test("^[0-9]+$")) | tonumber] | max? // empty | tostring ) as $max
    | if ($max != "" and (.builds[.latest] | not)) then .latest = $max else . end
  ' "$file" >"$tmp"
  write_if_changed "$file" "$tmp" "pruned non-master builds from legacy/$platform"
}

for product in "${PRODUCTS[@]}"; do
  for platform in "${PLATFORMS[@]}"; do
    line="$("$SCRIPTS/discover.sh" "$product" "$platform")"
    version="${line%%$'\t'*}"
    url="${line#*$'\t'}"
    if [[ "$product" == legacy ]] && ! is_master_url "$url"; then
      echo "refusing non-master legacy URL: $url" >&2
      exit 1
    fi
    upsert "$product" "$platform" "$version" "$url"
  done
done

upsert_legacy_recommended win32
upsert_legacy_recommended linux
prune_legacy_non_master win32
prune_legacy_non_master linux

for product in "${PRODUCTS[@]}"; do
  for platform in "${PLATFORMS[@]}"; do
    file="$(channel_file "$product" "$platform")"
    before="$(cksum <"$file" | awk '{print $1" "$2}')"
    prune_retention "$product" "$platform"
    after="$(cksum <"$file" | awk '{print $1" "$2}')"
    if [[ "$before" != "$after" ]]; then
      changed=1
      echo "pruned retention $product/$platform (minBuild $(policy_min_build "$product"))"
    fi
  done
done

prev_index="$(mktemp)"
cp versions/index.json "$prev_index"
write_index "$now"
if ! cmp -s "$prev_index" versions/index.json; then
  changed=1
fi
rm -f "$prev_index"

"$SCRIPTS/validate.sh"

if [[ "$changed" -eq 1 ]]; then
  echo "catalog changed"
  exit 0
fi
echo "catalog unchanged"
exit 0
