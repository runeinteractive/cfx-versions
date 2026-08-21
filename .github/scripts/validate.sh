#!/usr/bin/env bash
# validate.sh — catalog invariants (no network)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
source "$(dirname "$0")/common.sh"
need jq

errors=0
err() { echo "error: $*" >&2; errors=$((errors + 1)); }

[[ -f versions/policy.json ]] || { echo "missing versions/policy.json" >&2; exit 1; }
[[ -f versions/index.json ]] || { echo "missing versions/index.json" >&2; exit 1; }

policy_schema="$(jq -r '.schemaVersion // empty' versions/policy.json)"
[[ "$policy_schema" == "$SCHEMA_VERSION" ]] || err "policy schemaVersion want $SCHEMA_VERSION got ${policy_schema:-none}"

for product in "${PRODUCTS[@]}"; do
  min="$(policy_min_build "$product")"
  [[ -n "$min" ]] || err "policy.retention.$product.minBuild missing"
done

index_schema="$(jq -r '.schemaVersion // empty' versions/index.json)"
[[ "$index_schema" == "$SCHEMA_VERSION" ]] || err "index schemaVersion want $SCHEMA_VERSION got ${index_schema:-none}"
jq -e '.updatedAt | type == "string" and length > 0' versions/index.json >/dev/null \
  || err "index.updatedAt missing"

for product in "${PRODUCTS[@]}"; do
  for platform in "${PLATFORMS[@]}"; do
    key="$(channel_key "$product" "$platform")"
    file="$(channel_file "$product" "$platform")"
    min="$(policy_min_build "$product")"

    [[ -f "$file" ]] || { err "missing $file"; continue; }

    schema="$(jq -r '.schemaVersion // empty' "$file")"
    [[ "$schema" == "$SCHEMA_VERSION" ]] || err "$file schemaVersion want $SCHEMA_VERSION got ${schema:-none}"

    have_product="$(jq -r '.product // empty' "$file")"
    have_platform="$(jq -r '.platform // empty' "$file")"
    [[ "$have_product" == "$product" ]] || err "$file product want $product got $have_product"
    [[ "$have_platform" == "$platform" ]] || err "$file platform want $platform got $have_platform"

    latest="$(jq -r '.latest // empty' "$file")"
    [[ -n "$latest" ]] || err "$file latest missing"
    jq -e --arg v "$latest" '.builds[$v] != null' "$file" >/dev/null \
      || err "$file latest $latest not in builds"

    stable="$(jq -r '.stable | if . == null then "" else tostring end' "$file")"
    if [[ -n "$stable" ]]; then
      jq -e --arg v "$stable" '.builds[$v] != null' "$file" >/dev/null \
        || err "$file stable $stable not in builds"
    fi

    # Build entries: numeric id, non-empty url + seenAt; legacy must be master.
    while IFS=$'\t' read -r id url || [[ -n "$id" ]]; do
      id="${id%$'\r'}"; url="${url%$'\r'}"
      [[ -z "$id" ]] && continue
      [[ "$id" =~ ^[0-9]+$ ]] || err "$file build id not numeric: $id"
      [[ -n "$url" ]] || err "$file build $id url empty"
      if [[ "$product" == legacy ]] && ! is_master_url "$url"; then
        err "$file build $id not a master URL"
      fi
      if [[ -n "$min" ]] && (( 10#$id < min )) && [[ "$id" != "$latest" ]] && [[ "$id" != "$stable" ]]; then
        err "$file build $id below retention minBuild $min"
      fi
    done < <(jq -r '.builds | to_entries[] | [.key, (.value.url // "")] | @tsv' "$file")

    jq -e '[.builds[].seenAt] | all(type == "string" and length > 0)' "$file" >/dev/null \
      || err "$file build seenAt missing"

    # Index must mirror channel pins.
    idx_latest="$(jq -r --arg k "$key" '.channels[$k].latest // empty' versions/index.json)"
    idx_stable="$(jq -r --arg k "$key" '.channels[$k].stable | if . == null then "" else tostring end' versions/index.json)"
    idx_path="$(jq -r --arg k "$key" '.channels[$k].path // empty' versions/index.json)"
    [[ "$idx_latest" == "$latest" ]] || err "index $key latest want $latest got $idx_latest"
    [[ "$idx_stable" == "$stable" ]] || err "index $key stable want ${stable:-null} got ${idx_stable:-null}"
    [[ "$idx_path" == "$file" ]] || err "index $key path want $file got $idx_path"
  done
done

# Index must not list unknown channels.
while IFS= read -r key || [[ -n "$key" ]]; do
  key="${key%$'\r'}"
  [[ -z "$key" ]] && continue
  known=0
  for product in "${PRODUCTS[@]}"; do
    for platform in "${PLATFORMS[@]}"; do
      if [[ "$key" == "$(channel_key "$product" "$platform")" ]]; then
        known=1
      fi
    done
  done
  [[ "$known" -eq 1 ]] || err "index unknown channel $key"
done < <(jq -r '.channels | keys[]' versions/index.json)

if [[ "$errors" -ne 0 ]]; then
  echo "validate failed ($errors)" >&2
  exit 1
fi
echo "validate ok"
