#!/usr/bin/env bash
set -euo pipefail

SCHEMA_VERSION=1
PRODUCTS=(legacy enhanced)
PLATFORMS=(win32 linux)

need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }

channel_file() {
  echo "versions/$1/$2.json"
}

channel_key() {
  echo "$1/$2"
}

# Legacy FXServer: only …/master/… (never feature/*).
is_master_url() {
  [[ "${1:-}" == *"/master/"* ]]
}

legacy_artifact_root() {
  case "$1" in
    win32) echo "build_server_windows" ;;
    linux) echo "build_proot_linux" ;;
    *) echo "unknown platform: $1" >&2; return 1 ;;
  esac
}

legacy_artifact_file() {
  case "$1" in
    win32) echo "server.zip" ;;
    linux) echo "fx.tar.xz" ;;
    *) echo "unknown platform: $1" >&2; return 1 ;;
  esac
}

legacy_master_url() {
  local platform="$1" folder="$2"
  printf 'https://runtime.fivem.net/artifacts/fivem/%s/master/%s/%s\n' \
    "$(legacy_artifact_root "$platform")" \
    "$folder" \
    "$(legacy_artifact_file "$platform")"
}

# Active build folder from Cfx master listing HTML on stdin.
# Example: 34629-cb3c120b0a46c07ff1513cb0cbf8c4b4b38fb05b
legacy_master_folder_from_stdin() {
  local folder
  folder="$(sed -n 's/.*is-active[^>]*href="\.\/\([0-9][0-9]*-[a-f0-9]*\)\/.*/\1/p' | head -1)"
  if [[ -z "$folder" ]]; then
    folder="$(grep -oE 'href="\./[0-9]+-[a-f0-9]+/' | grep -oE '[0-9]+-[a-f0-9]+' | sort -t- -k1,1n | tail -1)"
  fi
  [[ -n "$folder" ]] || return 1
  printf '%s\n' "$folder"
}

policy_min_build() {
  local product="$1"
  jq -r --arg p "$product" '.retention[$p].minBuild // empty' versions/policy.json
}

# Rewrite versions/index.json from channel files. Arg: ISO-8601 UTC timestamp.
write_index() {
  local updatedAt="$1"
  local tmp product platform key file
  tmp="$(mktemp)"

  jq -n \
    --argjson schemaVersion "$SCHEMA_VERSION" \
    --arg updatedAt "$updatedAt" \
    '{ schemaVersion: $schemaVersion, updatedAt: $updatedAt, channels: {} }' >"$tmp"

  for product in "${PRODUCTS[@]}"; do
    for platform in "${PLATFORMS[@]}"; do
      key="$(channel_key "$product" "$platform")"
      file="$(channel_file "$product" "$platform")"
      jq \
        --arg key "$key" \
        --arg path "$file" \
        --argjson meta "$(jq '{latest, stable}' "$file")" \
        '.channels[$key] = ($meta + {path: $path})' \
        "$tmp" >"${tmp}.next"
      mv "${tmp}.next" "$tmp"
    done
  done

  # Stable key order for deterministic diffs.
  jq -S . "$tmp" >"${tmp}.sorted"
  mv "${tmp}.sorted" versions/index.json
  rm -f "$tmp"
}

# Keep builds >= minBuild, plus latest/stable pins. Sorted keys for clean diffs.
prune_retention() {
  local product="$1" platform="$2"
  local file min tmp
  file="$(channel_file "$product" "$platform")"
  min="$(policy_min_build "$product")"
  [[ -n "$min" ]] || return 0

  tmp="$(mktemp)"
  jq \
    --argjson min "$min" \
    '
      . as $root
      | .builds |= (
          with_entries(
            select(
              (.key | test("^[0-9]+$") | not)
              or (.key | tonumber) >= $min
              or .key == $root.latest
              or (.key == $root.stable)
            )
          )
          | to_entries
          | sort_by(.key | tonumber)
          | from_entries
        )
    ' "$file" >"$tmp"
  mv "$tmp" "$file"
}
